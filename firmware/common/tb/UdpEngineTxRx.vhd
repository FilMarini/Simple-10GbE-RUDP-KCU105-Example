-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Simulation Testbed for testing the EthMac module
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'SLAC Firmware Standard Library', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.EthMacPkg.all;

entity UdpEngineTxRx is
  port (
    clk_i            : in  std_logic;
    rst_i            : in  std_logic;
    phyReady_i       : in  std_logic;
    -- Input data
    ibClientMaster   : in  AxiStreamMasterType;
    ibClientSlave    : out AxiStreamSlaveType;
    obClientMaster   : out AxiStreamMasterType;
    obClientSlave    : in  AxiStreamSlaveType;
    -- Output packet
    ibMacMasterSniff : out AxiStreamMasterType;
    -- Recovered data
    obServerMaster   : out AxiStreamMasterType;
    obServerSlave    : in  AxiStreamSlaveType;
    -- XGMII Sniff
    xgmiiTxD         : out slv(63 downto 0);
    xgmiiTxC         : out slv(7 downto 0);
    xgmiiRxDin       : in  slv(63 downto 0);
    xgmiiRxCin       : in  slv(7 downto 0);
    xgmiiRxDout      : out slv(63 downto 0);
    xgmiiRxCout      : out slv(7 downto 0);
    -- Control XGMII RX
    xgmiiRxFlow      : in  sl := '0'
    );
end UdpEngineTxRx;

architecture rtl of UdpEngineTxRx is

  constant TPD_G : time := 1 ns;

  constant MAC_ADDR_C : Slv48Array(1 downto 0) := (
    -- 0 => x"010300564400",               --00:44:56:00:03:01
    0 => x"00000027000A",               --0a:00:27:00:00:00
    -- 1 => x"020300564400");              --00:44:56:00:03:02
    1 => x"78D23C270008");              --08:00:27:3c:d2:78

  constant IP_ADDR_C : Slv32Array(1 downto 0) := (
    0 => x"0138A8C0",                   -- 192.168.56.01
    -- 1 => x"0B02A8C0");                  -- 192.168.2.11
    1 => x"0B38A8C0");                  -- 192.168.56.11

  signal obMacMasters     : AxiStreamMasterArray(1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal obMacSlaves      : AxiStreamSlaveArray(1 downto 0)  := (others => AXI_STREAM_SLAVE_INIT_C);
  signal ibMacMasters     : AxiStreamMasterArray(1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal ibMacSlaves      : AxiStreamSlaveArray(1 downto 0)  := (others => AXI_STREAM_SLAVE_INIT_C);
  signal obMacMasterSniff : AxiStreamMasterType              := AXI_STREAM_MASTER_INIT_C;

  signal ethConfig    : EthMacConfigArray(1 downto 0) := (others => ETH_MAC_CONFIG_INIT_C);
  signal phyD         : Slv64Array(1 downto 0)        := (others => (others => '0'));
  signal phyC         : Slv8Array(1 downto 0)         := (others => (others => '0'));
  signal s_phyDMacRx0 : slv(63 downto 0)              := (others => '0');
  signal s_phyCMacRx0 : slv(7 downto 0)               := (others => '0');

begin

  -----------------------------------------------------------------------------
  -- Assegnations
  -----------------------------------------------------------------------------
  ibMacMasterSniff <= ibMacMasters(0);
  obMacMasterSniff <= obMacMasters(0);
  xgmiiTxD         <= PhyD(1);
  xgmiiTxC         <= PhyC(1);
  xgmiiRxDout      <= PhyD(0);
  xgmiiRxCout      <= PhyC(0);

  PhyD(0) <= xgmiiRxDin when xgmiiRxFlow = '1' else
             s_phyDMacRx0;
  PhyC(0) <= xgmiiRxCin when xgmiiRxFlow = '1' else
             s_phyCMacRx0;

  ----------------------
  -- IPv4/ARP/UDP Engine
  ----------------------
  U_UDP_Client : entity surf.UdpEngineWrapper
    generic map (
      -- Simulation Generics
      TPD_G               => TPD_G,
      -- UDP Server Generics
      SERVER_EN_G         => false,
      -- UDP Client Generics
      CLIENT_EN_G         => true,
      CLIENT_SIZE_G       => 1,
      CLIENT_PORTS_G      => (0 => 4791),
      CLIENT_EXT_CONFIG_G => true)
    port map (
      -- Local Configurations
      localMac            => MAC_ADDR_C(0),
      localIp             => IP_ADDR_C(0),
      -- Remote Configurations
      -- clientRemotePort(0) => x"0020",  -- PORT = 8192 = 0x2000 (0x0020 in big endianness)
      clientRemotePort(0) => x"B712",  -- PORT = 4791 = 0x12B7 (0xB712 in big endianness)
      clientRemoteIp(0)   => IP_ADDR_C(1),
      -- Interface to Ethernet Media Access Controller (MAC)
      obMacMaster         => obMacMasters(0),
      obMacSlave          => obMacSlaves(0),
      ibMacMaster         => ibMacMasters(0),  -- also cocotb
      ibMacSlave          => ibMacSlaves(0),   -- also cocotb
      -- Interface to UDP Server engine(s)
      obClientMasters(0)  => obClientMaster,
      obClientSlaves(0)   => obClientSlave,
      ibClientMasters(0)  => ibClientMaster,
      ibClientSlaves(0)   => ibClientSlave,
      -- Clock and Reset
      clk                 => clk_i,
      rst                 => rst_i
      );

  --------------------
  -- Ethernet MAC core
  --------------------
  U_MAC0 : entity surf.EthMacTop
    generic map (
      TPD_G         => TPD_G,
      PHY_TYPE_G    => "XGMII",
      PRIM_CONFIG_G => EMAC_AXIS_CONFIG_C)
    port map (
      -- DMA Interface
      primClk         => clk_i,
      primRst         => rst_i,
      ibMacPrimMaster => ibMacMasters(0),
      ibMacPrimSlave  => ibMacSlaves(0),
      obMacPrimMaster => obMacMasters(0),
      obMacPrimSlave  => obMacSlaves(0),
      -- Ethernet Interface
      ethClk          => clk_i,
      ethRst          => rst_i,
      ethConfig       => ethConfig(0),
      phyReady        => phyReady_i,
      -- XGMII PHY Interface
      xgmiiRxd        => phyD(0),
      xgmiiRxc        => phyC(0),
      xgmiiTxd        => phyD(1),
      xgmiiTxc        => phyC(1)
      );
  ethConfig(0).macAddress <= MAC_ADDR_C(0);

  U_MAC1 : entity surf.EthMacTop
    generic map (
      TPD_G         => TPD_G,
      PHY_TYPE_G    => "XGMII",
      PRIM_CONFIG_G => EMAC_AXIS_CONFIG_C)
    port map (
      -- DMA Interface
      primClk         => clk_i,
      primRst         => rst_i,
      ibMacPrimMaster => ibMacMasters(1),
      ibMacPrimSlave  => ibMacSlaves(1),
      obMacPrimMaster => obMacMasters(1),
      obMacPrimSlave  => obMacSlaves(1),
      -- Ethernet Interface
      ethClk          => clk_i,
      ethRst          => rst_i,
      ethConfig       => ethConfig(1),
      phyReady        => phyReady_i,
      -- XGMII PHY Interface
      xgmiiRxd        => phyD(1),
      xgmiiRxc        => phyC(1),
      xgmiiTxd        => s_phyDMacRx0,
      xgmiiTxc        => s_phyCMacRx0
      );
  ethConfig(1).macAddress <= MAC_ADDR_C(1);

  ----------------------
  -- IPv4/ARP/UDP Engine
  ----------------------
  U_UDP_Server : entity surf.UdpEngineWrapper
    generic map (
      -- Simulation Generics
      TPD_G          => TPD_G,
      -- UDP Server Generics
      SERVER_EN_G    => true,
      SERVER_SIZE_G  => 1,
      SERVER_PORTS_G => (0 => 8192),
      -- UDP Client Generics
      CLIENT_EN_G    => false)
    port map (
      -- Local Configurations
      localMac           => MAC_ADDR_C(1),
      localIp            => IP_ADDR_C(1),
      -- Interface to Ethernet Media Access Controller (MAC)
      obMacMaster        => obMacMasters(1),
      obMacSlave         => obMacSlaves(1),
      ibMacMaster        => ibMacMasters(1),
      ibMacSlave         => ibMacSlaves(1),
      -- Interface to UDP Server engine(s)
      obServerMasters(0) => obServerMaster,  -- cocotb
      obServerSlaves(0)  => obServerSlave,   -- cocotb
      ibServerMasters(0) => AXI_STREAM_MASTER_INIT_C,
      ibServerSlaves     => open,
      -- Clock and Reset
      clk                => clk_i,
      rst                => rst_i
      );


end rtl;
