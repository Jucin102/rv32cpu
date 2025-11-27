Richard Bi, Kevin Liu, Bryan Zhang: Chig Bungus

Checkpoint 2 Progress Report

## Functionalities Implemented:
OOO Execution for ALU operations (superscalar in progress, only some modules compatible with SS parameter)
- Rename and dispatch (Bryan)
- ALU reservation stations (Richard)
- Issue arbiter (Richard)
- Adder functional units (Richard)
- Multiplier functional units (Richard)
- Regfile (Richard)
- CDB arbiter(Richard)
- RAT (Kevin)
- ROB (Kevin)
- RRF (Kevin)
- Free list (Kevin)
- Types.sv (Chig Bungoo)

## Testing Strategy:
We hooked up everything to the DUT in top_tb and ran the ooo and dependency tests thuroughly. After RVFI is passed, we ran spike, and everything worked.

## Timing and area
Area: 47802
Timing slack: 0.000094
Power: 903335

## Roadmap:
- Take care of starvation issue when reservation station > 2
- Implement store/load
    - buffer
- Implement branch
- Make modules compatible with superscalar execution