//! The drawing of the terminal client.

use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color as RColor, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::app::App;

/// Draw the whole screen.
pub fn draw(frame: &mut Frame, app: &mut App) {
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(3), Constraint::Length(1)])
        .split(frame.size());

    let panes = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(40), Constraint::Percentage(60)])
        .split(rows[0]);

    let items: Vec<ListItem> = app
        .rows
        .iter()
        .map(|row| ListItem::new(format!("{}  {}", row.path, row.title)))
        .collect();

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(app.list_title()),
        )
        .highlight_style(
            Style::default()
                .bg(RColor::Indexed(238))
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, panes[0], &mut app.state);

    let preview = Paragraph::new(app.preview.as_str())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" {} ", app.preview_title)),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(preview, panes[1]);

    let line = Paragraph::new(app.input_line());
    frame.render_widget(line, rows[1]);
}
