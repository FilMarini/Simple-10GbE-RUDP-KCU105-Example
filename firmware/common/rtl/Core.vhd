-------------------------------------------------------------------------------
-- Title      : Core
-- Project    : 
-------------------------------------------------------------------------------
-- File       : Core.vhd<simplest-10gbe-rudp>
-- Author     : Filippo Marini  <filippo.marini@pd.infn.it>
-- Company    : INFN Padova
-- Created    : 2023-08-02
-- Last update: 2023-09-07
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2023 INFN Padova
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2023-08-02  1.0      filippo Created
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.RssiPkg.all;

library unisim;
use unisim.vcomponents.all;

entity Core is
  generic (
    TPD_G        : time             := 1 ns;
    N_STREAMS_G  : positive         := 1;
    BUILD_INFO_G : BuildInfoType;
    SIMULATION_G : boolean          := false;
    IP_ADDR_G    : slv(31 downto 0) := x"0A02A8C0";  -- 192.168.2.10
    DHCP_G       : boolean          := false);
  port (
    -- Clock and Reset
    axilClk_o         : out sl;
    axilRst_o         : out sl;
    -- AXI-Stream Interface
    ibRudpMaster_i    : in  AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
    ibRudpSlave_o     : out AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);
    obRudpMaster_o    : out AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
    obRudpSlave_i     : in  AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);
    -- AXI-Lite Interface
    axilReadMaster_o  : out AxiLiteReadMasterType;
    axilReadSlave_i   : in  AxiLiteReadSlaveType;
    axilWriteMaster_o : out AxiLiteWriteMasterType;
    axilWriteSlave_i  : in  AxiLiteWriteSlaveType;
    -- SYSMON Ports
    vPIn_i            : in  sl;
    vNIn_i            : in  sl;
    -- System Ports
    extRst_i          : in  sl;
    heartbeat_o       : out sl;
    phyReady_o        : out sl;
    rssiLinkUp_o      : out slv(1 + (N_STREAMS_G - 1) downto 0);
    axilUserRst_o     : out sl;
    -- ETH GT Pins
    ethClkP_i         : in  sl;
    ethClkN_i         : in  sl;
    ethRxP_i          : in  sl;
    ethRxN_i          : in  sl;
    ethTxP_o          : out sl;
    ethTxN_o          : out sl);
end Core;

architecture rtl of Core is

  constant VERSION_INDEX_C : natural := 0;
  constant SYS_MON_INDEX_C : natural := 1;
  constant ETH_INDEX_C     : natural := 2;
  constant APP_INDEX_C     : natural := 3;

  constant NUM_AXIL_MASTERS_C : positive := 4;

  constant XBAR_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := (
    VERSION_INDEX_C => (baseAddr => x"0000_0000", addrBits => 16, connectivity => x"FFFF"),
    SYS_MON_INDEX_C => (baseAddr => x"0001_0000", addrBits => 16, connectivity => x"FFFF"),
    ETH_INDEX_C     => (baseAddr => x"0010_0000", addrBits => 20, connectivity => x"FFFF"),
    APP_INDEX_C     => (baseAddr => x"8000_0000", addrBits => 31, connectivity => x"FFFF")
    );

  signal s_clk              : std_logic;
  signal s_rst              : std_logic;
  signal s_mAxilWriteMaster : AxiLiteWriteMasterType;
  signal s_mAxilWriteSlave  : AxiLiteWriteSlaveType;
  signal s_mAxilReadMaster  : AxiLiteReadMasterType;
  signal s_mAxilReadSlave   : AxiLiteReadSlaveType;
  signal s_axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal s_axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_SLVERR_C);
  signal s_axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal s_axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_SLVERR_C);

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clk heartbeat
  -----------------------------------------------------------------------------
  U_Heartbeat : entity surf.Heartbeat
    generic map (
      TPD_G        => TPD_G,
      PERIOD_IN_G  => 6.4E-9,           --units of seconds
      PERIOD_OUT_G => 1.0E-0)           --units of seconds
    port map (
      clk => s_clk,
      rst => s_rst,
      o   => heartbeat_o
      );

  -----------------------------------------------------------------------------
  -- Ethernet
  -----------------------------------------------------------------------------
  GEN_ETH : if (SIMULATION_G = false) generate

    U_Rudp : entity work.Rudp
      generic map (
        TPD_G            => TPD_G,
        N_STREAMS_G      => N_STREAMS_G,
        IP_ADDR_G        => IP_ADDR_G,
        DHCP_G           => DHCP_G,
        AXIL_BASE_ADDR_G => XBAR_CONFIG_C(ETH_INDEX_C).baseAddr
        )
      port map (
        -- System Ports
        extRst_i           => extRst_i,
        -- Ethernet Status
        phyReady_o         => phyReady_o,
        rssiLinkUp_o       => rssiLinkUp_o,
        -- Clock and Reset
        axilClk_o          => s_clk,
        axilRst_o          => s_rst,
        -- AXI-Stream Interface
        ibRudpMaster_i     => ibRudpMaster_i,
        ibRudpSlave_o      => ibRudpSlave_o,
        obRudpMaster_o     => obRudpMaster_o,
        obRudpSlave_i      => obRudpSlave_i,
        -- Master AXI-Lite Interface
        mAxilReadMaster_o  => s_mAxilReadMaster,
        mAxilReadSlave_i   => s_mAxilReadSlave,
        mAxilWriteMaster_o => s_mAxilWriteMaster,
        mAxilWriteSlave_i  => s_mAxilWriteSlave,
        -- Slave AXI-Lite Interfaces
        sAxilReadMaster_i  => s_axilReadMasters(ETH_INDEX_C),
        sAxilReadSlave_o   => s_axilReadSlaves(ETH_INDEX_C),
        sAxilWriteMaster_i => s_axilWriteMasters(ETH_INDEX_C),
        sAxilWriteSlave_o  => s_axilWriteSlaves(ETH_INDEX_C),
        -- ETH GT Pins
        ethClkP_i          => ethClkP_i,
        ethClkN_i          => ethClkN_i,
        ethRxP_i           => ethRxP_i,
        ethRxN_i           => ethRxN_i,
        ethTxP_o           => ethTxP_o,
        ethTxN_o           => ethTxN_o
        );

    axilClk_o <= s_clk;
    axilRst_o <= s_rst;

  end generate;

  GEN_ROGUE_TCP : if (SIMULATION_G = true) generate

    U_ClkRst : entity surf.ClkRst
      generic map (
        CLK_PERIOD_G      => 6.4 ns,
        RST_START_DELAY_G => 0 ns,
        RST_HOLD_TIME_G   => 1 us)
      port map (
        clkP => s_clk,
        rst  => s_rst
        );

    U_TcpToAxiLite : entity surf.RogueTcpMemoryWrap
      generic map (
        TPD_G      => TPD_G,
        PORT_NUM_G => 10000)            -- TCP Ports [10000,10001]
      port map (
        axilClk         => s_clk,
        axilRst         => s_rst,
        axilReadMaster  => s_mAxilReadMaster,
        axilReadSlave   => s_mAxilReadSlave,
        axilWriteMaster => s_mAxilWriteMaster,
        axilWriteSlave  => s_mAxilWriteSlave
        );

    U_TcpToAxiStream : entity surf.RogueTcpStreamWrap
      generic map (
        TPD_G         => TPD_G,
        PORT_NUM_G    => 10002,         -- TCP Ports [10002,10003]
        SSI_EN_G      => true,
        AXIS_CONFIG_G => RSSI_AXIS_CONFIG_C)
      port map (
        axisClk     => s_clk,
        axisRst     => s_rst,
        sAxisMaster => ibRudpMaster_i,
        sAxisSlave  => ibRudpSlave_o,
        mAxisMaster => obRudpMaster_o,
        mAxisSlave  => obRudpSlave_i
        );

    axilClk_o <= s_clk;
    axilRst_o <= s_rst;

  end generate;

  ---------------------------
  -- AXI-Lite Crossbar Module
  ---------------------------
  U_XBAR : entity surf.AxiLiteCrossbar
    generic map (
      TPD_G              => TPD_G,
      NUM_SLAVE_SLOTS_G  => 1,
      NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
      MASTERS_CONFIG_G   => XBAR_CONFIG_C)
    port map (
      sAxiWriteMasters(0) => s_mAxilWriteMaster,
      sAxiWriteSlaves(0)  => s_mAxilWriteSlave,
      sAxiReadMasters(0)  => s_mAxilReadMaster,
      sAxiReadSlaves(0)   => s_mAxilReadSlave,
      mAxiWriteMasters    => s_axilWriteMasters,
      mAxiWriteSlaves     => s_axilWriteSlaves,
      mAxiReadMasters     => s_axilReadMasters,
      mAxiReadSlaves      => s_axilReadSlaves,
      axiClk              => s_clk,
      axiClkRst           => s_rst
      );

  ---------------------------
  -- AXI-Lite: Version Module
  ---------------------------
  U_AxiVersion : entity surf.AxiVersion
    generic map (
      TPD_G           => TPD_G,
      BUILD_INFO_G    => BUILD_INFO_G,
      CLK_PERIOD_G    => (1.0/156.25E+6),
      XIL_DEVICE_G    => "ULTRASCALE",
      USE_SLOWCLK_G   => true,
      EN_DEVICE_DNA_G => true,
      EN_ICAP_G       => true)
    port map (
      slowClk        => s_clk,
      axiReadMaster  => s_axilReadMasters(VERSION_INDEX_C),
      axiReadSlave   => s_axilReadSlaves(VERSION_INDEX_C),
      axiWriteMaster => s_axilWriteMasters(VERSION_INDEX_C),
      axiWriteSlave  => s_axilWriteSlaves(VERSION_INDEX_C),
      userReset      => axilUserRst_o,
      axiClk         => s_clk,
      axiRst         => s_rst
      );

  --------------------------
  -- AXI-Lite: SYSMON Module
  --------------------------
  U_SysMon : entity work.Sysmon
    generic map (
      TPD_G => TPD_G
      )
    port map (
      axiReadMaster  => s_axilReadMasters(SYS_MON_INDEX_C),
      axiReadSlave   => s_axilReadSlaves(SYS_MON_INDEX_C),
      axiWriteMaster => s_axilWriteMasters(SYS_MON_INDEX_C),
      axiWriteSlave  => s_axilWriteSlaves(SYS_MON_INDEX_C),
      axiClk         => s_clk,
      axiRst         => s_rst,
      vPIn           => vPIn_i,
      vNIn           => vNIn_i
      );

  -----------------------------------
  -- Map the Application AXI-Lite Bus
  -----------------------------------
  axilReadMaster_o               <= s_axilReadMasters(APP_INDEX_C);
  s_axilReadSlaves(APP_INDEX_C)  <= axilReadSlave_i;
  axilWriteMaster_o              <= s_axilWriteMasters(APP_INDEX_C);
  s_axilWriteSlaves(APP_INDEX_C) <= axilWriteSlave_i;



end architecture rtl;
