pub mod mock;
pub mod real;

use crate::scope::Oscilloscope;
use crate::feedback_controller::FeedbackController;
use std::sync::Arc;
use std::path::Path;

pub fn create_oscilloscope() -> Arc<dyn Oscilloscope + Send + Sync> {
    if std::env::var("RP_MOCK").is_ok() {
        println!("RP_MOCK set, using MockOscilloscope");
        Arc::new(mock::MockOscilloscope::new())
    } else if Path::new("/dev/mem").exists() {
        println!("Detected /dev/mem, using RealOscilloscope");
        Arc::new(real::RealOscilloscope::new())
    } else {
        println!("/dev/mem not found, using MockOscilloscope");
        Arc::new(mock::MockOscilloscope::new())
    }
}

pub fn create_feedback_controller() -> Arc<dyn FeedbackController + Send + Sync> {
    if std::env::var("RP_MOCK").is_ok() {
        println!("RP_MOCK set, using MockFeedbackController");
        Arc::new(mock::MockFeedbackController::new())
    } else if Path::new("/dev/mem").exists() {
        println!("Detected /dev/mem, using RealFeedbackController");
        Arc::new(real::RealFeedbackController::new())
    } else {
        println!("/dev/mem not found, using MockFeedbackController");
        Arc::new(mock::MockFeedbackController::new())
    }
}
