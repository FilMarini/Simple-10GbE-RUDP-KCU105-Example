-------------------------------------------------------------------------------
-- Title      : RUDP
-- Project    : 
-------------------------------------------------------------------------------
-- File       : Rudp.vhd<simplest-10gbe-rudp>
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
use surf.EthMacPkg.all;
use surf.RssiPkg.all;

library unisim;
use unisim.vcomponents.all;

entity Rudp is
  generic (
    TPD_G            : time             := 1 ns;
    N_STREAMS_G      : positive         := 1;
    IP_ADDR_G        : slv(31 downto 0) := x"0A02A8C0";  -- 192.168.2.10
    DHCP_G           : boolean          := false;
    AXIL_BASE_ADDR_G : slv(31 downto 0));
  port (
    -- System Ports
    extRst_i           : in  sl;
    -- Ethernet Status
    phyReady_o         : out sl;
    rssiLinkUp_o       : out slv(1 + (N_STREAMS_G - 1) downto 0);
    -- Clock and Reset
    axilClk_o          : out sl;
    axilRst_o          : out sl;
    -- AXI-Stream Interface
    ibRudpMaster_i     : in  AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
    ibRudpSlave_o      : out AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);
    obRudpMaster_o     : out AxiStreamMasterArray(N_STREAMS_G - 1 downto 0);
    obRudpSlave_i      : in  AxiStreamSlaveArray(N_STREAMS_G - 1 downto 0);
    -- Master AXI-Lite Interface
    mAxilReadMaster_o  : out AxiLiteReadMasterType;
    mAxilReadSlave_i   : in  AxiLiteReadSlaveType;
    mAxilWriteMaster_o : out AxiLiteWriteMasterType;
    mAxilWriteSlave_i  : in  AxiLiteWriteSlaveType;
    -- Slave AXI-Lite Interfaces
    sAxilReadMaster_i  : in  AxiLiteReadMasterType;
    sAxilReadSlave_o   : out AxiLiteReadSlaveType;
    sAxilWriteMaster_i : in  AxiLiteWriteMasterType;
    sAxilWriteSlave_o  : out AxiLiteWriteSlaveType;
    -- ETH GT Pins
    ethClkP_i          : in  sl;
    ethClkN_i          : in  sl;
    ethRxP_i           : in  sl;
    ethRxN_i           : in  sl;
    ethTxP_o           : out sl;
    ethTxN_o           : out sl);
end Rudp;

architecture rtl of Rudp is

  function f_ports_idx (
    n_streams : positive)
    return IntegerArray is
    variable ports_array : IntegerArray(n_streams - 1 downto 0);
  begin  -- function f_ports
    for i in 0 to n_streams - 1 loop
      ports_array(i) := i + 1;
    end loop;  -- i
    return ports_array;
  end function f_ports_idx;

  function f_ports (
    server_size_c      : positive;
    udp_srv_srp_idx_c  : natural;
    udp_srv_data_idx_c : IntegerArray)
    return PositiveArray is
    variable server_ports : PositiveArray(server_size_c-1 downto 0);
  begin  -- function f_ports
    server_ports(udp_srv_srp_idx_c) := 8192;
    for i in 0 to udp_srv_data_idx_c'length - 1 loop
      server_ports(udp_srv_data_idx_c(i)) := 8193 + i;
    end loop;  -- i
    return server_ports;
  end function f_ports;

  constant PHY_INDEX_C      : natural := 0;
  constant UDP_INDEX_C      : natural := 1;
  constant RSSI_INDEX_C     : natural := 2;                  -- 2:(2+NS)
  constant AXIS_MON_INDEX_C : natural := (3 + N_STREAMS_G);  -- (3+NS):((3+NS)+(NS-1))

  constant NUM_AXIL_MASTERS_C : positive := (3 + (N_STREAMS_G * 2));
  constant XBAR_CONFIG_C      : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0)
    := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 20, 16);

  constant CLK_FREQUENCY_C : real := 156.25E+6;  -- In units of Hz

  -- UDP constants
  constant UDP_SRV_SRP_IDX_C  : natural := 0;
  constant UDP_SRV_DATA_IDX_C : IntegerArray(N_STREAMS_G-1 downto 0)
    := f_ports_idx(N_STREAMS_G);
  constant SERVER_SIZE_C  : positive := 1 + N_STREAMS_G;
  constant SERVER_PORTS_C : PositiveArray(SERVER_SIZE_C-1 downto 0)
    := f_ports(SERVER_SIZE_C, UDP_SRV_SRP_IDX_C, UDP_SRV_DATA_IDX_C);

  -- RSSI constants
  constant RSSI_SIZE_C : positive := 1;  -- Implementing only 1 VC per RSSI link
  constant AXIS_CONFIG_C : AxiStreamConfigArray(RSSI_SIZE_C-1 downto 0) := (
    0 => RSSI_AXIS_CONFIG_C);  -- Only using 64 bit AXI stream configuration

  signal s_ethClk           : std_logic;
  signal s_ethRst           : std_logic;
  signal s_axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal s_axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_SLVERR_C);
  signal s_axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal s_axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_SLVERR_C);
  signal s_efuse            : slv(31 downto 0);
  signal s_localMac         : slv(47 downto 0);
  signal s_localIp          : slv(31 downto 0);
  signal s_extReset         : std_logic;
  signal s_ibMacMaster      : AxiStreamMasterType;
  signal s_ibMacSlave       : AxiStreamSlaveType;
  signal s_obMacMaster      : AxiStreamMasterType;
  signal s_obMacSlave       : AxiStreamSlaveType;
  signal s_obServerMasters  : AxiStreamMasterArray(SERVER_SIZE_C-1 downto 0);
  signal s_obServerSlaves   : AxiStreamSlaveArray(SERVER_SIZE_C-1 downto 0);
  signal s_ibServerMasters  : AxiStreamMasterArray(SERVER_SIZE_C-1 downto 0);
  signal s_ibServerSlaves   : AxiStreamSlaveArray(SERVER_SIZE_C-1 downto 0);
  -- One RSSI per UDP port (which is why SERVER_SIZE_C used instead of SERVER_SIZE_C)
  signal s_rssiIbMasters    : AxiStreamMasterArray(SERVER_SIZE_C-1 downto 0);
  signal s_rssiIbSlaves     : AxiStreamSlaveArray(SERVER_SIZE_C-1 downto 0);
  signal s_rssiObMasters    : AxiStreamMasterArray(SERVER_SIZE_C-1 downto 0);
  signal s_rssiObSlaves     : AxiStreamSlaveArray(SERVER_SIZE_C-1 downto 0);

begin  -- architecture rtl

  axilClk_o <= s_ethClk;
  axilRst_o <= s_ethRst;

  -----------------------------------------------------------------------------
  -- Axi-Lite XBAR
  -----------------------------------------------------------------------------
  U_XBAR : entity surf.AxiLiteCrossbar
    generic map (
      TPD_G              => TPD_G,
      NUM_SLAVE_SLOTS_G  => 1,
      NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
      MASTERS_CONFIG_G   => XBAR_CONFIG_C)
    port map (
      axiClk              => s_ethClk,
      axiClkRst           => s_ethRst,
      sAxiWriteMasters(0) => sAxilWriteMaster_i,
      sAxiWriteSlaves(0)  => sAxilWriteSlave_o,
      sAxiReadMasters(0)  => sAxilReadMaster_i,
      sAxiReadSlaves(0)   => sAxilReadSlave_o,
      mAxiWriteMasters    => s_axilWriteMasters,
      mAxiWriteSlaves     => s_axilWriteSlaves,
      mAxiReadMasters     => s_axilReadMasters,
      mAxiReadSlaves      => s_axilReadSlaves
      );

  --------------------------------------------------
  -- Example of using EFUSE to store the MAC Address
  --------------------------------------------------
  U_EFuse : EFUSE_USR
    port map (
      EFUSEUSR => s_efuse
      );

  -------------------------------------
  -- 08:00:56:XX:XX:XX (big endian SLV)
  -------------------------------------
  s_localMac(23 downto 0)  <= x"56_00_08";  -- 08:00:56 is the SLAC Vendor ID
  s_localMac(47 downto 24) <= s_efuse(31 downto 8);

  -----------------------------------------------
  -- Default IP address before DHCP IP assignment
  -----------------------------------------------
  s_localIp <= IP_ADDR_G;

  -----------------
  -- Power Up Reset
  -----------------
  U_PwrUpRst : entity surf.PwrUpRst
    generic map (
      TPD_G      => TPD_G,
      DURATION_G => 156250000)
    port map (
      arst   => extRst_i,
      clk    => s_ethClk,
      rstOut => s_extReset);

  ----------------------------------
  -- 10 GigE PHY/MAC Ethernet Layers
  ----------------------------------
  U_10GigE : entity surf.TenGigEthGthUltraScaleWrapper
    generic map (
      TPD_G        => TPD_G,
      NUM_LANE_G   => 1,
      PAUSE_EN_G   => true,             -- Enable ETH pause
      EN_AXI_REG_G => true)             -- Enable diagnostic AXI-Lite interface
    port map (
      -- Local Configurations
      localMac(0)            => s_localMac,
      -- Streaming DMA Interface
      dmaClk(0)              => s_ethClk,
      dmaRst(0)              => s_ethRst,
      dmaIbMasters(0)        => s_obMacMaster,
      dmaIbSlaves(0)         => s_obMacSlave,
      dmaObMasters(0)        => s_ibMacMaster,
      dmaObSlaves(0)         => s_ibMacSlave,
      -- Slave AXI-Lite Interface
      axiLiteClk(0)          => s_ethClk,
      axiLiteRst(0)          => s_ethRst,
      axiLiteReadMasters(0)  => s_axilReadMasters(PHY_INDEX_C),
      axiLiteReadSlaves(0)   => s_axilReadSlaves(PHY_INDEX_C),
      axiLiteWriteMasters(0) => s_axilWriteMasters(PHY_INDEX_C),
      axiLiteWriteSlaves(0)  => s_axilWriteSlaves(PHY_INDEX_C),
      -- Misc. Signals
      extRst                 => s_extReset,
      coreClk                => s_ethClk,
      coreRst                => s_ethRst,
      phyReady(0)            => phyReady_o,
      -- MGT Clock Port 156.25 MHz
      gtClkP                 => ethClkP_i,
      gtClkN                 => ethClkN_i,
      -- MGT Ports
      gtTxP(0)               => ethTxP_o,
      gtTxN(0)               => ethTxN_o,
      gtRxP(0)               => ethRxP_i,
      gtRxN(0)               => ethRxN_i
      );

  ------------------------------------
  -- IPv4/ARP/UDP/DHCP Ethernet Layers
  ------------------------------------
  U_UDP : entity surf.UdpEngineWrapper
    generic map (
      -- Simulation Generics
      TPD_G          => TPD_G,
      -- UDP Server Generics
      SERVER_EN_G    => true,           -- UDP Server only
      SERVER_SIZE_G  => SERVER_SIZE_C,
      SERVER_PORTS_G => SERVER_PORTS_C,
      -- UDP Client Generics
      CLIENT_EN_G    => false,          -- UDP Server only
      -- General IPv4/ARP/DHCP Generics
      DHCP_G         => DHCP_G,
      CLK_FREQ_G     => CLK_FREQUENCY_C,
      COMM_TIMEOUT_G => 10)             -- Timeout used for ARP and DHCP
    port map (
      -- Local Configurations
      localMac        => s_localMac,
      localIp         => s_localIp,
      -- Interface to Ethernet Media Access Controller (MAC)
      obMacMaster     => s_obMacMaster,
      obMacSlave      => s_obMacSlave,
      ibMacMaster     => s_ibMacMaster,
      ibMacSlave      => s_ibMacSlave,
      -- Interface to UDP Server engine(s)
      obServerMasters => s_obServerMasters,
      obServerSlaves  => s_obServerSlaves,
      ibServerMasters => s_ibServerMasters,
      ibServerSlaves  => s_ibServerSlaves,
      -- AXI-Lite Interface
      axilReadMaster  => s_axilReadMasters(UDP_INDEX_C),
      axilReadSlave   => s_axilReadSlaves(UDP_INDEX_C),
      axilWriteMaster => s_axilWriteMasters(UDP_INDEX_C),
      axilWriteSlave  => s_axilWriteSlaves(UDP_INDEX_C),
      -- Clock and Reset
      clk             => s_ethClk,
      rst             => s_ethRst
      );

  ------------------------------------------
  -- Software's RSSI Server Interface @ 8192
  ------------------------------------------
  GEN_VEC :
  for i in 0 to (1 + (N_STREAMS_G - 1)) generate
    U_RssiServer : entity surf.RssiCoreWrapper
      generic map (
        TPD_G              => TPD_G,
        PIPE_STAGES_G      => 1,
        SERVER_G           => true,
        APP_ILEAVE_EN_G    => true,
        MAX_SEG_SIZE_G     => ite(i = 0, 1024, 8192),  -- 1kB for SRPv3, 8KB for AXI stream
        APP_STREAMS_G      => RSSI_SIZE_C,
        CLK_FREQUENCY_G    => CLK_FREQUENCY_C,
        WINDOW_ADDR_SIZE_G => ite(i = 0, 4, 5),  -- 2^4 buffers for SRPv3, 2^5 buffers for AXI stream
        MAX_RETRANS_CNT_G  => 16,
        APP_AXIS_CONFIG_G  => AXIS_CONFIG_C,
        TSP_AXIS_CONFIG_G  => EMAC_AXIS_CONFIG_C)
      port map (
        clk_i                => s_ethClk,
        rst_i                => s_ethRst,
        openRq_i             => '1',
        rssiConnected_o      => rssiLinkUp_o(i),
        -- Application Layer Interface
        sAppAxisMasters_i(0) => s_rssiIbMasters(i),
        sAppAxisSlaves_o(0)  => s_rssiIbSlaves(i),
        mAppAxisMasters_o(0) => s_rssiObMasters(i),
        mAppAxisSlaves_i(0)  => s_rssiObSlaves(i),
        -- Transport Layer Interface
        sTspAxisMaster_i     => s_obServerMasters(i),
        sTspAxisSlave_o      => s_obServerSlaves(i),
        mTspAxisMaster_o     => s_ibServerMasters(i),
        mTspAxisSlave_i      => s_ibServerSlaves(i),
        -- AXI-Lite Interface
        axiClk_i             => s_ethClk,
        axiRst_i             => s_ethRst,
        axilReadMaster       => s_axilReadMasters(RSSI_INDEX_C+i),
        axilReadSlave        => s_axilReadSlaves(RSSI_INDEX_C+i),
        axilWriteMaster      => s_axilWriteMasters(RSSI_INDEX_C+i),
        axilWriteSlave       => s_axilWriteSlaves(RSSI_INDEX_C+i)
        );
  end generate GEN_VEC;

  ------------------------------------------------------------------
  -- RSSI[0] @ UDP Port(SERVER_PORTS_C[0]) = Register access control
  ------------------------------------------------------------------
  U_SRPv3 : entity surf.SrpV3AxiLite
    generic map (
      TPD_G               => TPD_G,
      SLAVE_READY_EN_G    => true,
      GEN_SYNC_FIFO_G     => true,
      AXI_STREAM_CONFIG_G => RSSI_AXIS_CONFIG_C)
    port map (
      -- Streaming Slave (Rx) Interface (sAxisClk domain)
      sAxisClk         => s_ethClk,
      sAxisRst         => s_ethRst,
      sAxisMaster      => s_rssiObMasters(0),
      sAxisSlave       => s_rssiObSlaves(0),
      -- Streaming Master (Tx) Data Interface (mAxisClk domain)
      mAxisClk         => s_ethClk,
      mAxisRst         => s_ethRst,
      mAxisMaster      => s_rssiIbMasters(0),
      mAxisSlave       => s_rssiIbSlaves(0),
      -- Master AXI-Lite Interface (axilClk domain)
      axilClk          => s_ethClk,
      axilRst          => s_ethRst,
      mAxilReadMaster  => mAxilReadMaster_o,
      mAxilReadSlave   => mAxilReadSlave_i,
      mAxilWriteMaster => mAxilWriteMaster_o,
      mAxilWriteSlave  => mAxilWriteSlave_i
      );

  ---------------------------------------------------------------
  -- RSSI[1+i] @ UDP Port(SERVER_PORTS_C[1+i]) = AXI Stream Interface
  ---------------------------------------------------------------
  GEN_RSSI_AT_UDP : for i in 0 to N_STREAMS_G - 1 generate
    s_rssiIbMasters(1+i) <= ibRudpMaster_i(i);
    ibRudpSlave_o(i)     <= s_rssiIbSlaves(1+i);
    obRudpMaster_o(i)    <= s_rssiObMasters(1+i);
    s_rssiObSlaves(1+i)  <= obRudpSlave_i(i);
  end generate GEN_RSSI_AT_UDP;

  ------------------------
  -- AXI Stream Monitoring
  ------------------------
  GEN_AXISMON : for i in 0 to N_STREAMS_G - 1 generate
    U_AXIS_MON : entity surf.AxiStreamMonAxiL
      generic map(
        TPD_G            => TPD_G,
        COMMON_CLK_G     => true,
        AXIS_CLK_FREQ_G  => CLK_FREQUENCY_C,
        AXIS_NUM_SLOTS_G => 2,
        AXIS_CONFIG_G    => RSSI_AXIS_CONFIG_C)
      port map(
        -- AXIS Stream Interface
        axisClk          => s_ethClk,
        axisRst          => s_ethRst,
        axisMasters(0)   => s_rssiIbMasters(1+i),
        axisMasters(1)   => s_rssiObMasters(1+i),
        axisSlaves(0)    => s_rssiIbSlaves(1+i),
        axisSlaves(1)    => s_rssiObSlaves(1+i),
        -- AXI lite slave port for register access
        axilClk          => s_ethClk,
        axilRst          => s_ethRst,
        sAxilWriteMaster => s_axilWriteMasters(AXIS_MON_INDEX_C+i),
        sAxilWriteSlave  => s_axilWriteSlaves(AXIS_MON_INDEX_C+i),
        sAxilReadMaster  => s_axilReadMasters(AXIS_MON_INDEX_C+i),
        sAxilReadSlave   => s_axilReadSlaves(AXIS_MON_INDEX_C+i)
        );
  end generate GEN_AXISMON;

end architecture rtl;
