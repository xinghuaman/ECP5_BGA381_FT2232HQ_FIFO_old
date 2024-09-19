# ECP5/FT2232HQ Board
This project aims to implement a High Speed USB device using the Lattice Semiconductor ECP5 FPGA coupled with a FT2232HQ operating in synchronous FIFO mode. If all goes well an extension board with a BNC connector will be built to serialize high resolution audio.

## Software
The Verilog software is located in the [/hdl](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/tree/main/hdl) directory.

## How to setup KiCAD
Checkout the project and open it. In the Configure Paths dialog add: Name: ECP5_BGA381_FT2232HQ_FIFO and Path: "The full path to the GitHub directory"/GitHub/ECP5_BGA381_FT2232HQ_FIFO

In the Manage Symbol Libraries click the Project Specific Libraries and add: Name: ECP5_BGA381_FT2232HQ_FIFO and Library Path: ${ECP5_BGA381_FT2232HQ_FIFO}/symbols/Symbols.kicad_sym

In the Manage Footprint Libraries click the Project Specific Libraries and add: Name: ECP5_BGA381_FT2232HQ_FIFO and Library Path: ${ECP5_BGA381_FT2232HQ_FIFO}/footprints/Footprints.pretty

## Project Status
The board should be back from manufacturing at PCBWay on Oct. 24th 2024.

[Schematic PDF](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/blob/main/kicad/ECP5.pdf)

![Board rendering](https://github.com/gildobjanschi/ECP5_BGA381_FT2232HQ_FIFO/blob/main/ECP5.jpg)
