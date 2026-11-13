"""PoliSim reference evaluator (the oracle).

A deliberately naive implementation of the model-file format and step semantics. It is
the specification in executable form: the Rust engine must reproduce its state hash on
every step. It is not a prototype of the engine and is never optimised.
"""

from .expr import FormulaError, SimError
from .model import ModelError, Scenario, load_model, load_scenario
from .sim import Simulation, from_scenario

__all__ = ["FormulaError", "ModelError", "Scenario", "SimError", "Simulation",
           "from_scenario", "load_model", "load_scenario"]
