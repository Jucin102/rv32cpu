Richard Bi, Kevin Liu, Bryan Zhang: Chig Bungus

Checkpoint 3 Progress Report

## Functionalities Implemented:
Support for control instructions and memory instructions. 
- Updated existing modules to be compatible with control instructions and misprediction. (Everyone)
- Implemented a queue for the targets of control instructions (Everyone)
- Load-store queue (Kevin)
- Cacheline adaptor (Bryan)
- Memory issue arbiter (Richard)
- Updated types.sv (Everyone)

## Testing Strategy:
We hooked up everything to the DUT in top_tb and ran quicksort, compression, rsa, and coremark. After RVFI is passed, we ran spike, and everything worked.

## Timing and area
Area: 305469.872657
Arrival time: 2.25 ns
Power: 5687149.5000

## Roadmap:
- Take care of starvation issue when reservation station > 2 (will fix for superscalar)
- Support superscalar 
- Decide on which branch predictor we want to implement