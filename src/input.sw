mod simulation::{SimulationInput}

struct InputLogic {

}

impl InputLogic {
    #[host_call] // is needed to tell Swamp that this will be called by a host (Lily2D)
    fn tick(mut self) -> SimulationInput {
        SimulationInput {

        }
    }
}
