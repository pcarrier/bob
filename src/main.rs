use iced::widget::{column, text};
use iced::{Element, Task};

fn main() -> iced::Result {
    iced::application("Hello World - Iced", HelloWorld::update, HelloWorld::view)
        .run()
}

#[derive(Default)]
struct HelloWorld;

impl HelloWorld {
    fn update(&mut self, _message: ()) -> Task<()> {
        Task::none()
    }

    fn view(&self) -> Element<()> {
        column![
            text("Hello, world!").size(50),
        ]
        .padding(20)
        .into()
    }
}
