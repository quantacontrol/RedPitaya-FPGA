use axum::{
    extract::{State, Json},
    response::IntoResponse,
    routing::{get, post},
    Router,
};
use tower_http::{
    cors::CorsLayer,
    services::ServeDir,
};
use std::sync::Arc;
use tokio::net::TcpListener;

mod scope;
mod feedback_controller;
mod hal;

use scope::{Oscilloscope, ScopeConfig};
use feedback_controller::{FeedbackController, FeedbackConfig, ControlMode};

struct AppState {
    scope: Arc<dyn Oscilloscope + Send + Sync>,
    feedback_ctrl: Arc<dyn FeedbackController + Send + Sync>,
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create oscilloscope and feedback controller instances (Mock or Real)
    let scope = hal::create_oscilloscope();
    let feedback_ctrl = hal::create_feedback_controller();
    let state = Arc::new(AppState { scope, feedback_ctrl });

    let frontend_path = std::env::var("FRONTEND_PATH")
        .unwrap_or_else(|_| "../frontend/dist".to_string());
    
    let serve_dir = ServeDir::new(&frontend_path)
        .append_index_html_on_directories(true);
    
    let app = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/v1/scope/data", get(get_scope_data))
        .route("/api/v1/scope/config", post(set_scope_config))
        .route("/api/v1/feedback/config", get(get_feedback_config))
        .route("/api/v1/feedback/config", post(set_feedback_config))
        .route("/api/v1/feedback/mode", post(set_feedback_mode))
        .route("/api/v1/feedback/test", get(get_feedback_test))
        .fallback_service(serve_dir)
        .layer(CorsLayer::permissive())
        .with_state(state);

    // Run server
    let listener = TcpListener::bind("0.0.0.0:3000").await.unwrap();
    println!("Server listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

async fn health_check() -> &'static str {
    "OK"
}

async fn get_scope_data(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.scope.acquire().await {
        Ok(data) => (axum::http::StatusCode::OK, data),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.into_bytes()),
    }
}

async fn set_scope_config(
    State(state): State<Arc<AppState>>,
    Json(config): Json<ScopeConfig>,
) -> impl IntoResponse {
    match state.scope.set_config(config) {
        Ok(_) => (axum::http::StatusCode::OK, "Config updated"),
        Err(_) => (axum::http::StatusCode::BAD_REQUEST, "Error updating config"),
    }
}

async fn get_feedback_config(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.feedback_ctrl.get_config() {
        Ok(config) => (axum::http::StatusCode::OK, Json(config)).into_response(),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e).into_response(),
    }
}

async fn set_feedback_config(
    State(state): State<Arc<AppState>>,
    Json(config): Json<FeedbackConfig>,
) -> impl IntoResponse {
    match state.feedback_ctrl.set_config(&config) {
        Ok(_) => (axum::http::StatusCode::OK, "Feedback config updated").into_response(),
        Err(e) => (axum::http::StatusCode::BAD_REQUEST, e).into_response(),
    }
}

async fn set_feedback_mode(
    State(state): State<Arc<AppState>>,
    Json(mode): Json<ControlMode>,
) -> impl IntoResponse {
    match state.feedback_ctrl.set_mode(mode) {
        Ok(_) => (axum::http::StatusCode::OK, "Mode set").into_response(),
        Err(e) => (axum::http::StatusCode::BAD_REQUEST, e).into_response(),
    }
}

async fn get_feedback_test(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    match state.feedback_ctrl.read_test_register() {
        Ok(val) => (axum::http::StatusCode::OK, format!("0x{:08x}", val)),
        Err(e) => (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e),
    }
}
