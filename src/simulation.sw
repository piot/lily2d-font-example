struct SimulationInput {
}

struct ExampleSimulation {
    time: Int
}


impl ExampleSimulation {
    fn new() -> ExampleSimulation {
        ExampleSimulation {..}
    }

    #[host_call]
    fn tick(mut self, _input: SimulationInput) {
        .time += 1
    }
}
