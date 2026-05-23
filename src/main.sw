mod render::{ExampleRender}
mod simulation::{ExampleSimulation, SimulationInput}
mod input::{InputLogic}

anchor render = ExampleRender::new()
anchor simulation = ExampleSimulation::new()
anchor input = InputLogic {..}
anchor input_return = SimulationInput {..}
