##############################################################################
## This file is part of 'Simple-10GbE-RUDP-KCU105-Example'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'Simple-10GbE-RUDP-KCU105-Example', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################

##############################################################################
# I/O Constraints
##############################################################################

set_property PACKAGE_PIN U4 [get_ports ethTxP]
set_property PACKAGE_PIN U3 [get_ports ethTxN]
set_property PACKAGE_PIN T2 [get_ports ethRxP]
set_property PACKAGE_PIN T1 [get_ports ethRxN]

set_property PACKAGE_PIN P6 [get_ports ethClkP]
set_property PACKAGE_PIN P5 [get_ports ethClkN]

set_property -dict { PACKAGE_PIN V12 IOSTANDARD ANALOG } [get_ports { vPIn }]
set_property -dict { PACKAGE_PIN W11 IOSTANDARD ANALOG } [get_ports { vNIn }]

set_property -dict { PACKAGE_PIN AN8 IOSTANDARD LVCMOS18 } [get_ports { extRst }]

set_property -dict { PACKAGE_PIN AL8  IOSTANDARD LVCMOS18 } [get_ports { sfpTxDisL }]
set_property -dict { PACKAGE_PIN AP10 IOSTANDARD LVCMOS18 } [get_ports { i2cRstL }]
set_property -dict { PACKAGE_PIN J24  IOSTANDARD LVCMOS18 } [get_ports { i2cScl }]
set_property -dict { PACKAGE_PIN J25  IOSTANDARD LVCMOS18 } [get_ports { i2cSda }]

set_property -dict { PACKAGE_PIN AP8 IOSTANDARD LVCMOS18 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN H23 IOSTANDARD LVCMOS18 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN P20 IOSTANDARD LVCMOS18 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN P21 IOSTANDARD LVCMOS18 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN N22 IOSTANDARD LVCMOS18 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN M22 IOSTANDARD LVCMOS18 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN R23 IOSTANDARD LVCMOS18 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN P23 IOSTANDARD LVCMOS18 } [get_ports { led[7] }]

set_property -dict { PACKAGE_PIN G26 IOSTANDARD LVCMOS18 } [get_ports { flashCsL }]  ; # QSPI1_CS_B
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS18 } [get_ports { flashMosi }] ; # QSPI1_IO[0]
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS18 } [get_ports { flashMiso }] ; # QSPI1_IO[1]
set_property -dict { PACKAGE_PIN R21 IOSTANDARD LVCMOS18 } [get_ports { flashWp }]   ; # QSPI1_IO[2]
set_property -dict { PACKAGE_PIN R22 IOSTANDARD LVCMOS18 } [get_ports { flashHoldL }]; # QSPI1_IO[3]

set_property -dict { PACKAGE_PIN K20 IOSTANDARD LVCMOS18 } [get_ports { emcClk }]

# On-Board System clock
set_property ODT RTT_48 [get_ports "sysClkN"]
set_property PACKAGE_PIN AK16 [get_ports "sysClkN"]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "sysClkN"]
set_property PACKAGE_PIN AK17 [get_ports "sysClkP"]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "sysClkP"]
set_property ODT RTT_48 [get_ports "sysClkP"]

# SGMII/Ext. PHY
set_property PACKAGE_PIN P25 [get_ports ethRxN]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports ethRxN]
set_property PACKAGE_PIN P24 [get_ports ethRxP]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports ethRxP]
set_property PACKAGE_PIN M24 [get_ports ethTxN]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports ethTxN]
set_property PACKAGE_PIN N24 [get_ports ethTxP]
set_property IOSTANDARD DIFF_HSTL_I_18 [get_ports ethTxP]
set_property PACKAGE_PIN N26 [get_ports ethClkN]
set_property IOSTANDARD LVDS_25 [get_ports ethClkN]
set_property PACKAGE_PIN P26 [get_ports ethClkP]
set_property IOSTANDARD LVDS_25 [get_ports ethClkP]

create_clock -name sysClkP -period 3.333 [get_ports {sysClkP}]
create_clock -name lvdsClkP   -period 1.600 [get_ports {gEthClkP}]
create_generated_clock -name ethClk625MHz [get_pins {U_Core/GEN_ETH.U_Rudp/Sgmii88E1111LvdsUltraScale_1/U_1GigE/U_PLL/CLKOUT0}]
create_generated_clock -name ethClk312MHz [get_pins {U_Core/GEN_ETH.U_Rudp/Sgmii88E1111LvdsUltraScale_1/U_1GigE/U_PLL/CLKOUT1}]
create_generated_clock -name ethClk125MHz [get_pins {U_Core/GEN_ETH.U_Rudp/Sgmii88E1111LvdsUltraScale_1/U_1GigE/U_sysClk125/O}]

set_property CLOCK_DELAY_GROUP ETH_CLK_GRP [get_nets {U_Core/GEN_ETH.U_Rudp/Sgmii88E1111LvdsUltraScale_1/U_1GigE/sysClk312}] [get_nets {U_Core/GEN_ETH.U_Rudp/Sgmii88E1111LvdsUltraScale_1/U_1GigE/sysClk625}]

set_clock_groups -asynchronous -group [get_clocks {ethClk312MHz}] -group [get_clocks {ethClk125MHz}]
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks {lvdsClkP}] -group [get_clocks -include_generated_clocks {sysClkP}]
##############################################################################
# Timing Constraints
##############################################################################

create_clock -name ethClkP -period  6.400 [get_ports {ethClkP}]

set_clock_groups -asynchronous -group [get_clocks ethClkP] -group [get_clocks -of_objects [get_pins {U_Core/GEN_ETH.U_Rudp/U_10GigE/GEN_LANE[0].TenGigEthGthUltraScale_Inst/U_TenGigEthRst/CLK156_BUFG_GT/O}]]
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks {lvdsClkP}] -group [get_clocks -include_generated_clocks {ethClkP}]

##############################################################################
# BITSTREAM: .bit file Configuration
##############################################################################

set_property CONFIG_VOLTAGE 1.8                      [current_design]
set_property CFGBVS GND                              [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE         [current_design]
set_property CONFIG_MODE SPIx8                       [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8         [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-1 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES      [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup       [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR Yes     [current_design]
set_property BITSTREAM.STARTUP.LCK_CYCLE NoWait      [current_design]
set_property BITSTREAM.STARTUP.MATCH_CYCLE NoWait    [current_design]
