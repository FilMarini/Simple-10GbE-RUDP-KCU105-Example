-------------------------------------------------------------------------------
-- Title      : Simple10GbeRudpKcu105ExampleRoceTb
-- Project    : 
-------------------------------------------------------------------------------
-- File       : Simple10GbeRudpKcu105ExampleRoceTb.vhd
-- Author     : Filippo Marini  <filippo.marini@pd.infn.it>
-- Company    : INFN Padova
-- Created    : 2025-02-26
-- Last update: 2025-02-26
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2025 INFN Padova
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2025-02-26  1.0      fmarini	Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.EthMacPkg.all;
use surf.RocePkg.all;

entity Simple10GbeRudpKcu105ExampleRoceTb is

  generic (
    USE_DMA_SERV_HDL_G : boolean := true
    );
  port (
    clk                        : in  std_logic;
    rst                        : in  std_logic;
    phyReady                   : in  std_logic;
    -- Work Req In
    s_work_req_valid           : in  std_logic;
    s_work_req_id              : in  std_logic_vector(63 downto 0);
    s_work_req_op_code         : in  std_logic_vector(3 downto 0);
    s_work_req_flags           : in  std_logic_vector(4 downto 0);
    s_work_req_raddr           : in  std_logic_vector(63 downto 0);
    s_work_req_rkey            : in  std_logic_vector(31 downto 0);
    s_work_req_len             : in  std_logic_vector(31 downto 0);
    s_work_req_laddr           : in  std_logic_vector(63 downto 0);
    s_work_req_lkey            : in  std_logic_vector(31 downto 0);
    s_work_req_sqpn            : in  std_logic_vector(23 downto 0);
    s_work_req_solicited       : in  std_logic;
    s_work_req_comp            : in  std_logic_vector(64 downto 0);
    s_work_req_swap            : in  std_logic_vector(64 downto 0);
    s_work_req_imm_dt          : in  std_logic_vector(32 downto 0);
    s_work_req_rkey_to_inv     : in  std_logic_vector(32 downto 0);
    s_work_req_srqn            : in  std_logic_vector(24 downto 0);
    s_work_req_dqpn            : in  std_logic_vector(24 downto 0);
    s_work_req_qkey            : in  std_logic_vector(32 downto 0);
    s_work_req_ready           : out std_logic;
    -- Work Completions
    m_work_comp_sq_valid       : out std_logic;
    m_work_comp_sq_id          : out std_logic_vector(63 downto 0);
    m_work_comp_sq_op_code     : out std_logic_vector(7 downto 0);
    m_work_comp_sq_flags       : out std_logic_vector(6 downto 0);
    m_work_comp_sq_status      : out std_logic_vector(4 downto 0);
    m_work_comp_sq_len         : out std_logic_vector(31 downto 0);
    m_work_comp_sq_pkey        : out std_logic_vector(15 downto 0);
    m_work_comp_sq_qpn         : out std_logic_vector(23 downto 0);
    m_work_comp_sq_imm_dt      : out std_logic_vector(32 downto 0);
    m_work_comp_sq_rkey_to_inv : out std_logic_vector(32 downto 0);
    m_work_comp_sq_ready       : in  std_logic;
    -- Metadata In
    s_meta_data_tvalid         : in  std_logic;
    s_meta_data_tdata          : in  std_logic_vector(302 downto 0);
    s_meta_data_tready         : out std_logic;
    -- Metadata Out
    m_meta_data_tvalid         : out std_logic;
    m_meta_data_tdata          : out std_logic_vector(275 downto 0);
    m_meta_data_tready         : in  std_logic;
    -- DMA Read Out
    m_dma_read_valid           : out std_logic;
    m_dma_read_initiator       : out std_logic_vector(3 downto 0);
    m_dma_read_sqpn            : out std_logic_vector(23 downto 0);
    m_dma_read_wr_id           : out std_logic_vector(63 downto 0);
    m_dma_read_start_addr      : out std_logic_vector(63 downto 0);
    m_dma_read_len             : out std_logic_vector(12 downto 0);
    m_dma_read_mr_idx          : out std_logic;
    m_dma_read_ready           : in  std_logic;
    -- DMA Read In
    s_dma_read_valid           : in  std_logic;
    s_dma_read_initiator       : in  std_logic_vector(3 downto 0);
    s_dma_read_sqpn            : in  std_logic_vector(23 downto 0);
    s_dma_read_wr_id           : in  std_logic_vector(63 downto 0);
    s_dma_read_is_resp_err     : in  std_logic;
    s_dma_read_data_stream     : in  std_logic_vector(289 downto 0);
    s_dma_read_ready           : out std_logic;
    -- XGMII Sniff
    xgmiiTxD                   : out slv(63 downto 0);
    xgmiiTxC                   : out slv(7 downto 0);
    xgmiiRxDin                 : in  slv(63 downto 0);
    xgmiiRxCin                 : in  slv(7 downto 0);
    xgmiiRxDout                : out slv(63 downto 0);
    xgmiiRxCout                : out slv(7 downto 0);
    -- Control XGMII RX
    xgmiiRxFlow                : in  sl
    );
end entity Simple10GbeRudpKcu105ExampleRoceTb;

architecture rtl of Simple10GbeRudpKcu105ExampleRoceTb is

  signal s_workReqMaster       : RoceWorkReqMasterType;
  signal s_workReqSlave        : RoceWorkReqSlaveType;
  signal s_workCompMaster      : RoceWorkCompMasterType;
  signal s_workCompSlave       : RoceWorkCompSlaveType;
  signal s_obUdpMaster         : AxiStreamMasterType;
  signal s_obUdpSlave          : AxiStreamSlaveType;
  signal s_ibUdpMaster         : AxiStreamMasterType;
  signal s_ibUdpSlave          : AxiStreamSlaveType;
  signal s_sAxisMetaDataMaster : AxiStreamMasterType;
  signal s_sAxisMetaDataSlave  : AxiStreamSlaveType;
  signal s_mAxisMetaDataMaster : AxiStreamMasterType;
  signal s_mAxisMetaDataSlave  : AxiStreamSlaveType;
  signal s_dmaReadRespMaster   : RoceDmaReadRespMasterType;
  signal s_dmaReadRespSlave    : RoceDmaReadRespSlaveType;
  signal s_dmaReadReqMaster    : RoceDmaReadReqMasterType;
  signal s_dmaReadReqSlave     : RoceDmaReadReqSlaveType;

  signal s_xgmiiTxD : slv(63 downto 0);
  signal s_xgmiiTxC : slv(7 downto 0);
  signal s_xgmiiRxD : slv(63 downto 0);
  signal s_xgmiiRxC : slv(7 downto 0);

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Interface
  -----------------------------------------------------------------------------
  -- Work Req
  s_workReqMaster <= ToRoceWorkReqMasterType(
    valid     => s_work_req_valid,
    id        => s_work_req_id,
    opCode    => s_work_req_op_code,
    flags     => s_work_req_flags,
    rAddr     => s_work_req_raddr,
    rKey      => s_work_req_rkey,
    len       => s_work_req_len,
    lAddr     => s_work_req_laddr,
    lKey      => s_work_req_lkey,
    sQpn      => s_work_req_sqpn,
    solicited => s_work_req_solicited,
    comp      => s_work_req_comp,
    swap      => s_work_req_swap,
    immDt     => s_work_req_imm_dt,
    rkeyToInv => s_work_req_rkey_to_inv,
    srqn      => s_work_req_srqn,
    dQpn      => s_work_req_dqpn,
    qKey      => s_work_req_qkey
    );
  s_work_req_ready <= s_workReqSlave.ready;
  -- Work Completions
  s_workCompSlave <= ToRoceWorkCompSlaveType(
    ready => m_work_comp_sq_ready
    );
  m_work_comp_sq_valid       <= s_workCompMaster.valid;
  m_work_comp_sq_id          <= s_workCompMaster.id;
  m_work_comp_sq_op_code     <= s_workCompMaster.opCode;
  m_work_comp_sq_flags       <= s_workCompMaster.flags;
  m_work_comp_sq_status      <= s_workCompMaster.status;
  m_work_comp_sq_len         <= s_workCompMaster.len;
  m_work_comp_sq_pkey        <= s_workCompMaster.pKey;
  m_work_comp_sq_qpn         <= s_workCompMaster.qpn;
  m_work_comp_sq_imm_dt      <= s_workCompMaster.immDt;
  m_work_comp_sq_rkey_to_inv <= s_workCompMaster.rkeyToInv;
  -- MetaData
  s_sAxisMetaDataMaster <= ToAxisMetadataMasterType(
    valid => s_meta_data_tvalid,
    data  => s_meta_data_tdata
    );
  s_meta_data_tready <= s_sAxisMetaDataSlave.tReady;
  m_meta_data_tdata  <= s_mAxisMetaDataMaster.tData(275 downto 0);
  m_meta_data_tvalid <= s_mAxisMetaDataMaster.tValid;
  s_mAxisMetaDataSlave <= ToAxisMetadataSlaveType(
    ready => m_meta_data_tready
    );
  -- Dma Read Req
  GEN_USE_DMA_SERV_REQ_HDL : if USE_DMA_SERV_HDL_G generate
    m_dma_read_valid      <= '0';
    m_dma_read_initiator  <= (others => '0');
    m_dma_read_sqpn       <= (others => '0');
    m_dma_read_wr_id      <= (others => '0');
    m_dma_read_start_addr <= (others => '0');
    m_dma_read_len        <= (others => '0');
    m_dma_read_mr_idx     <= '0';
  end generate GEN_USE_DMA_SERV_REQ_HDL;

  GEN_USE_DMA_SERV_REQ_PYT : if not USE_DMA_SERV_HDL_G generate
    s_dmaReadReqSlave <= ToDmaReadReqSlaveType(
      ready => m_dma_read_ready
      );
    m_dma_read_valid      <= s_dmaReadReqMaster.valid;
    m_dma_read_initiator  <= s_dmaReadReqMaster.initiator;
    m_dma_read_sqpn       <= s_dmaReadReqMaster.sQpn;
    m_dma_read_wr_id      <= s_dmaReadReqMaster.wrId;
    m_dma_read_start_addr <= s_dmaReadReqMaster.startAddr;
    m_dma_read_len        <= s_dmaReadReqMaster.len;
    m_dma_read_mr_idx     <= s_dmaReadReqMaster.mrIdx;
  end generate GEN_USE_DMA_SERV_REQ_PYT;
  -- Dma Read Resp
  GEN_USE_DMA_SERV_RESP_HDL : if USE_DMA_SERV_HDL_G generate
    s_dma_read_ready <= '0';
  end generate GEN_USE_DMA_SERV_RESP_HDL;

  GEN_USE_DMA_SERV_RESP_PYT : if not USE_DMA_SERV_HDL_G generate
    s_dmaReadRespMaster <= ToDmaReadRespMasterType(
      valid      => s_dma_read_valid,
      initiator  => s_dma_read_initiator,
      sqpn       => s_dma_read_sqpn,
      wrId       => s_dma_read_wr_id,
      isRespErr  => s_dma_read_is_resp_err,
      dataStream => s_dma_read_data_stream
      );
    s_dma_read_ready <= s_dmaReadRespSlave.ready;
  end generate GEN_USE_DMA_SERV_RESP_PYT;

  -----------------------------------------------------------------------------
  -- Blue-RDMA
  -----------------------------------------------------------------------------
  RoceEngineWrapper_1 : entity surf.RoceEngineWrapper
    generic map (
      EXT_ROCE_CONFIG_G => true
      )
    port map (
      RoceClk             => clk,
      RoceRst             => rst,
      workReqMaster       => s_workReqMaster,
      workReqSlave        => s_workReqSlave,
      workCompMaster      => s_workCompMaster,
      workCompSlave       => s_workCompSlave,
      obUdpMaster         => s_obUdpMaster,
      obUdpSlave          => s_obUdpSlave,
      ibUdpMaster         => s_ibUdpMaster,
      ibUdpSlave          => s_ibUdpSlave,
      sAxisMetaDataMaster => s_sAxisMetaDataMaster,
      sAxisMetaDataSlave  => s_sAxisMetaDataSlave,
      mAxisMetaDataMaster => s_mAxisMetaDataMaster,
      mAxisMetaDataSlave  => s_mAxisMetaDataSlave,
      dmaReadRespMaster   => s_dmaReadRespMaster,
      dmaReadRespSlave    => s_dmaReadRespSlave,
      dmaReadReqMaster    => s_dmaReadReqMaster,
      dmaReadReqSlave     => s_dmaReadReqSlave
      );

  -----------------------------------------------------------------------------
  -- Dma dummy server
  -----------------------------------------------------------------------------
  GEN_DMA_SER_HDL : if USE_DMA_SERV_HDL_G generate
    DmaDummyServer_1 : entity work.DmaDummyServer
      port map (
        RoceClk             => clk,
        RoceRst             => rst,
        dmaReadReqMaster_i  => s_dmaReadReqMaster,
        dmaReadReqSlave_o   => s_dmaReadReqSlave,
        dmaReadRespMaster_o => s_dmaReadRespMaster,
        dmaReadRespSlave_i  => s_dmaReadRespSlave);
  end generate GEN_DMA_SER_HDL;

  -----------------------------------------------------------------------------
  -- UDP engine TxRx
  -----------------------------------------------------------------------------
  UdpEngineTxRx_1 : entity work.UdpEngineTxRx
    port map (
      clk_i          => clk,
      rst_i          => rst,
      phyReady_i     => phyReady,
      ibClientMaster => s_ibUdpMaster,
      ibClientSlave  => s_ibUdpSlave,
      obClientMaster => s_obUdpMaster,
      obClientSlave  => s_obUdpSlave,
      -- obServerMaster => s_obServerMaster,
      obServerSlave  => AXI_STREAM_SLAVE_FORCE_C,
      xgmiiTxD       => xgmiiTxD,
      xgmiiTxC       => xgmiiTxC,
      xgmiiRxDin     => xgmiiRxDin,
      xgmiiRxCin     => xgmiiRxCin,
      xgmiiRxDout    => xgmiiRxDout,
      xgmiiRxCout    => xgmiiRxCout,
      xgmiiRxFlow    => xgmiiRxFlow
      );


end architecture rtl;
