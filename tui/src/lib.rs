//! The Lumen terminal client.
//!
//! The client has two halves: [`cli`] holds the commands that print or edit
//! a note and then get out of the way, and [`app`] holds the interactive
//! browser. [`ui`] draws the browser.

pub mod app;
pub mod cli;
pub mod ui;
