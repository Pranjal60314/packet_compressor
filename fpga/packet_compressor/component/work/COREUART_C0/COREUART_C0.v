//////////////////////////////////////////////////////////////////////
// Created by SmartDesign Thu Aug 27 19:01:53 2026
// Version: 2026.1 2026.1.0.17
//////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

//////////////////////////////////////////////////////////////////////
// Component Description (Tcl) 
//////////////////////////////////////////////////////////////////////
/*
# Exporting Component Description of COREUART_C0 to TCL
# Family: PolarFireSoC
# Part Number: MPFS095T-1FCSG325E
# Create and Configure the core component COREUART_C0
create_and_configure_core -core_vlnv {Actel:DirectCore:COREUART:5.7.100} -component_name {COREUART_C0} -params {\
"BAUD_VAL_FRCTN_EN:false"  \
"RX_FIFO:0"  \
"RX_LEGACY_MODE:0"  \
"TX_FIFO:0"  \
"USE_SOFT_FIFO:0"   }
# Exporting Component Description of COREUART_C0 to TCL done
*/

// COREUART_C0
module COREUART_C0(
    // Inputs
    BAUD_VAL,
    BIT8,
    CLK,
    CSN,
    DATA_IN,
    ODD_N_EVEN,
    OEN,
    PARITY_EN,
    RESET_N,
    RX,
    WEN,
    // Outputs
    DATA_OUT,
    FRAMING_ERR,
    OVERFLOW,
    PARITY_ERR,
    RXRDY,
    TX,
    TXRDY
);

//--------------------------------------------------------------------
// Input
//--------------------------------------------------------------------
input  [12:0] BAUD_VAL;
input         BIT8;
input         CLK;
input         CSN;
input  [7:0]  DATA_IN;
input         ODD_N_EVEN;
input         OEN;
input         PARITY_EN;
input         RESET_N;
input         RX;
input         WEN;
//--------------------------------------------------------------------
// Output
//--------------------------------------------------------------------
output [7:0]  DATA_OUT;
output        FRAMING_ERR;
output        OVERFLOW;
output        PARITY_ERR;
output        RXRDY;
output        TX;
output        TXRDY;
//--------------------------------------------------------------------
// Nets
//--------------------------------------------------------------------
wire   [12:0] BAUD_VAL;
wire          BIT8;
wire          CLK;
wire          CSN;
wire   [7:0]  DATA_IN;
wire   [7:0]  DATA_OUT_net_0;
wire          FRAMING_ERR_net_0;
wire          ODD_N_EVEN;
wire          OEN;
wire          OVERFLOW_net_0;
wire          PARITY_EN;
wire          PARITY_ERR_net_0;
wire          RESET_N;
wire          RX;
wire          RXRDY_net_0;
wire          TX_net_0;
wire          TXRDY_net_0;
wire          WEN;
wire   [7:0]  DATA_OUT_net_1;
wire          OVERFLOW_net_1;
wire          PARITY_ERR_net_1;
wire          RXRDY_net_1;
wire          TX_net_1;
wire          TXRDY_net_1;
wire          FRAMING_ERR_net_1;
//--------------------------------------------------------------------
// TiedOff Nets
//--------------------------------------------------------------------
wire   [2:0]  BAUD_VAL_FRACTION_const_net_0;
//--------------------------------------------------------------------
// Constant assignments
//--------------------------------------------------------------------
assign BAUD_VAL_FRACTION_const_net_0 = 3'h0;
//--------------------------------------------------------------------
// Top level output port assignments
//--------------------------------------------------------------------
assign DATA_OUT_net_1    = DATA_OUT_net_0;
assign DATA_OUT[7:0]     = DATA_OUT_net_1;
assign OVERFLOW_net_1    = OVERFLOW_net_0;
assign OVERFLOW          = OVERFLOW_net_1;
assign PARITY_ERR_net_1  = PARITY_ERR_net_0;
assign PARITY_ERR        = PARITY_ERR_net_1;
assign RXRDY_net_1       = RXRDY_net_0;
assign RXRDY             = RXRDY_net_1;
assign TX_net_1          = TX_net_0;
assign TX                = TX_net_1;
assign TXRDY_net_1       = TXRDY_net_0;
assign TXRDY             = TXRDY_net_1;
assign FRAMING_ERR_net_1 = FRAMING_ERR_net_0;
assign FRAMING_ERR       = FRAMING_ERR_net_1;
//--------------------------------------------------------------------
// Component instances
//--------------------------------------------------------------------
//--------COREUART_C0_COREUART_C0_0_COREUART   -   Actel:DirectCore:COREUART:5.7.100
COREUART_C0_COREUART_C0_0_COREUART #( 
        .BAUD_VAL_FRCTN_EN ( 0 ),
        .FAMILY            ( 27 ),
        .RX_FIFO           ( 0 ),
        .RX_LEGACY_MODE    ( 0 ),
        .TX_FIFO           ( 0 ) )
COREUART_C0_0(
        // Inputs
        .BAUD_VAL          ( BAUD_VAL ),
        .BIT8              ( BIT8 ),
        .CLK               ( CLK ),
        .CSN               ( CSN ),
        .DATA_IN           ( DATA_IN ),
        .ODD_N_EVEN        ( ODD_N_EVEN ),
        .OEN               ( OEN ),
        .PARITY_EN         ( PARITY_EN ),
        .RESET_N           ( RESET_N ),
        .RX                ( RX ),
        .WEN               ( WEN ),
        .BAUD_VAL_FRACTION ( BAUD_VAL_FRACTION_const_net_0 ), // tied to 3'h0 from definition
        // Outputs
        .DATA_OUT          ( DATA_OUT_net_0 ),
        .OVERFLOW          ( OVERFLOW_net_0 ),
        .PARITY_ERR        ( PARITY_ERR_net_0 ),
        .RXRDY             ( RXRDY_net_0 ),
        .TX                ( TX_net_0 ),
        .TXRDY             ( TXRDY_net_0 ),
        .FRAMING_ERR       ( FRAMING_ERR_net_0 ) 
        );


endmodule
