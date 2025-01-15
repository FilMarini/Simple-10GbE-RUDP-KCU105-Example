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
      BUILD_INFO_G : BuildInfoType;
      SIMULATION_G : boolean          := false;
      IP_ADDR_G    : slv(31 downto 0) := x"0A02A8C0";  -- 192.168.2.10
      PHY_BYPASS_G : false;
      MAC_BYPASS_G : false;
      DHCP_G       : boolean          := false);
   port (
      -- I2C Ports
      sfpTxDisL   : out   sl;
      i2cRstL     : out   sl;
      i2cScl      : inout sl;
      i2cSda      : inout sl;
      -- XADC Ports
      vPIn        : in    sl;
      vNIn        : in    sl;
      -- System Ports
      emcClk      : in    sl;
      extRst      : in    sl;
      led         : out   slv(7 downto 0);
      -- Boot Memory Ports
      flashCsL    : out   sl;
      flashMosi   : out   sl;
      flashMiso   : in    sl;
      flashHoldL  : out   sl;
      flashWp     : out   sl;
      -- ETH GT Pins
      ethClkP     : in    sl;
      ethClkN     : in    sl;
      ethRxP      : in    sl;
      ethRxN      : in    sl;
      ethTxP      : out   sl;
      ethTxN      : out   sl;
      -- XGMII PHY Interface (in case PHY is bypassed)
      xgmiiRxd    : in    slv(63 downto 0)    := (others => '0');
      xgmiiRxc    : in    slv(7 downto 0)     := (others => '0');
      xgmiiTxd    : out   slv(63 downto 0);
      xgmiiTxc    : out   slv(7 downto 0);
      -- UDP Interface (in case PHY is bypassed)
      udpRxMaster : in    AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
      udpRxSlave  : out   AxiStreamSlaveType;
      udpTxMaster : out   AxiStreamMasterType;
      udpTxSlave  : in    AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C
      );
end Simple10GbeRudpKcu105Example;

architecture top_level of Simple10GbeRudpKcu105Example is

   signal heartbeat  : sl;
   signal phyReady   : sl;
   signal rssiLinkUp : slv(1 downto 0);

   -- Clock and Reset
   signal axilClk : sl;
   signal axilRst : sl;

   -- AXI-Stream: Stream Interface
   signal ibRudpMaster : AxiStreamMasterType;
   signal ibRudpSlave  : AxiStreamSlaveType;
   signal obRudpMaster : AxiStreamMasterType;
   signal obRudpSlave  : AxiStreamSlaveType;

   -- AXI-Lite: Register Access
   signal axilReadMaster  : AxiLiteReadMasterType;
   signal axilReadSlave   : AxiLiteReadSlaveType;
   signal axilWriteMaster : AxiLiteWriteMasterType;
   signal axilWriteSlave  : AxiLiteWriteSlaveType;

begin

   led(7) <= '1';
   led(6) <= '0';
   led(5) <= heartbeat;
   led(4) <= axilRst;
   led(3) <= not(axilRst);
   led(2) <= rssiLinkUp(1);
   led(1) <= rssiLinkUp(0);
   led(0) <= phyReady;

   -----------------------
   -- Core Firmware Module
   -----------------------
   U_Core : entity work.Core
      generic map (
         TPD_G        => TPD_G,
         BUILD_INFO_G => BUILD_INFO_G,
         SIMULATION_G => SIMULATION_G,
         BUILD_10G_G  => true,          -- 10GbE
         IP_ADDR_G    => IP_ADDR_G,
         PHY_BYPASS_G => PHY_BYPASS_G,
         MAC_BYPASS_G => MAC_BYPASS_G,
         DHCP_G       => DHCP_G)
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
         axilWriteSlave  => axilWriteSlave,
         -- I2C Ports
         sfpTxDisL       => sfpTxDisL,
         i2cRstL         => i2cRstL,
         i2cScl          => i2cScl,
         i2cSda          => i2cSda,
         -- SYSMON Ports
         vPIn            => vPIn,
         vNIn            => vNIn,
         -- System Ports
         extRst          => extRst,
         emcClk          => emcClk,
         heartbeat       => heartbeat,
         phyReady        => phyReady,
         rssiLinkUp      => rssiLinkUp,
         -- Boot Memory Ports
         flashCsL        => flashCsL,
         flashMosi       => flashMosi,
         flashMiso       => flashMiso,
         flashHoldL      => flashHoldL,
         flashWp         => flashWp,
         -- ETH GT Pins
         ethClkP         => ethClkP,
         ethClkN         => ethClkN,
         ethRxP          => ethRxP,
         ethRxN          => ethRxN,
         ethTxP          => ethTxP,
         ethTxN          => ethTxN
         -- XGMII PHY Interface (in case PHY is bypassed)
         xgmiiRxd        => xgmiiRxd,
         xgmiiRxc        => xgmiiRxc,
         xgmiiTxd        => xgmiiTxd,
         xgmiiTxc        => xgmiiTxc,
         -- UDP Interface (in case PHY is bypassed)
         udpRxMaster     => udpRxMaster,
         udpRxSlave      => udpRxSlave,
         udpTxMaster     => udpTxMaster,
         udpTxSlave      => udpTxSlave
         );

   ------------------------------
   -- Application Firmware Module
   ------------------------------
   U_App : entity work.App
      generic map (
         TPD_G        => TPD_G,
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
