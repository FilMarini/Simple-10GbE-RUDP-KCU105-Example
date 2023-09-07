-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Simple 10G-BASER Example
-------------------------------------------------------------------------------
-- This file is part of 'Simple-10GbE-RUDP-KCU105-Example'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Simple-10GbE-RUDP-KCU105-Example', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

entity Simple10GbeRudpKcu105Example is
  generic (
    TPD_G        : time             := 1 ns;
    N_STREAMS_G  : positive         := 3;
    BUILD_INFO_G : BuildInfoType;
    SIMULATION_G : boolean          := false;
    IP_ADDR_G    : slv(31 downto 0) := x"0A02A8C0";  -- 192.168.2.10
    DHCP_G       : boolean          := false);
  port (
    -- XADC Ports
    vPIn       : in    sl;
    vNIn       : in    sl;
    -- System Ports
    extRst     : in    sl;
    led        : out   slv(7 downto 0);
    -- ETH GT Pins
    ethClkP    : in    sl;
    ethClkN    : in    sl;
    ethRxP     : in    sl;
    ethRxN     : in    sl;
    ethTxP     : out   sl;
    ethTxN     : out   sl);
end Simple10GbeRudpKcu105Example;

architecture top_level of Simple10GbeRudpKcu105Example is

  signal heartbeat  : sl;
  signal phyReady   : sl;
  signal rssiLinkUp : slv(1 + (N_STREAMS_G - 1) downto 0);

  -- Clock and Reset
  signal axilClk : sl;
  signal axilRst : sl;

  -- AXI-Stream: Stream Interface
  signal ibRudpMaster : AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
  signal ibRudpSlave  : AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);
  signal obRudpMaster : AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
  signal obRudpSlave  : AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);

  -- AXI-Lite: Register Access
  signal axilReadMaster  : AxiLiteReadMasterType;
  signal axilReadSlave   : AxiLiteReadSlaveType;
  signal axilWriteMaster : AxiLiteWriteMasterType;
  signal axilWriteSlave  : AxiLiteWriteSlaveType;

begin

  led(7) <= '1';
  led(6) <= '0';
  led(5) <= heartbeat;
  led(4) <= rssiLinkUp(3);
  led(3) <= rssiLinkUp(2);
  led(2) <= rssiLinkUp(1);
  led(1) <= rssiLinkUp(0);
  led(0) <= phyReady;

  -----------------------
  -- Core Firmware Module
  -----------------------
  U_Core : entity work.Core
    generic map (
      TPD_G        => TPD_G,
      N_STREAMS_G  => N_STREAMS_G,
      BUILD_INFO_G => BUILD_INFO_G,
      SIMULATION_G => SIMULATION_G,
      IP_ADDR_G    => IP_ADDR_G,
      DHCP_G       => DHCP_G)
    port map (
      -- Clock and Reset
      axilClk_o         => axilClk,
      axilRst_o         => axilRst,
      -- AXI-Stream Interface
      ibRudpMaster_i    => ibRudpMaster,
      ibRudpSlave_o     => ibRudpSlave,
      obRudpMaster_o    => obRudpMaster,
      obRudpSlave_i     => obRudpSlave,
      -- AXI-Lite Interface
      axilReadMaster_o  => axilReadMaster,
      axilReadSlave_i   => axilReadSlave,
      axilWriteMaster_o => axilWriteMaster,
      axilWriteSlave_i  => axilWriteSlave,
      -- SYSMON Ports
      vPIn_i            => vPIn,
      vNIn_i            => vNIn,
      -- System Ports
      extRst_i          => extRst,
      heartbeat_o       => heartbeat,
      phyReady_o        => phyReady,
      rssiLinkUp_o      => rssiLinkUp,
      axilUserRst_o     => open,
      -- ETH GT Pins
      ethClkP_i         => ethClkP,
      ethClkN_i         => ethClkN,
      ethRxP_i          => ethRxP,
      ethRxN_i          => ethRxN,
      ethTxP_o          => ethTxP,
      ethTxN_o          => ethTxN
      );

  ------------------------------
  -- Application Firmware Module
  ------------------------------
  U_App : entity work.App
    generic map (
      TPD_G        => TPD_G,
      N_STREAMS_G  => N_STREAMS_G,
      SIMULATION_G => SIMULATION_G)
    port map (
      -- Clock and Reset
      axilClk         => axilClk,
      axilRst         => axilRst,
      -- AXI-Stream Interface
      ibRudpMaster    => ibRudpMaster,
      ibRudpSlave     => ibRudpSlave,
      obRudpMaster    => obRudpMaster,
      obRudpSlave     => obRudpSlave,
      -- AXI-Lite Interface
      axilReadMaster  => axilReadMaster,
      axilReadSlave   => axilReadSlave,
      axilWriteMaster => axilWriteMaster,
      axilWriteSlave  => axilWriteSlave);

end top_level;
