-------------------------------------------------------------------------------
-- Title      : DmaDummyServer
-- Project    : 
-------------------------------------------------------------------------------
-- File       : DmaDummyServer.vhd
-- Author     : Filippo Marini  <filippo.marini@pd.infn.it>
-- Company    : INFN Padova
-- Created    : 2024-07-30
-- Last update: 2025-02-26
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2024 INFN Padova
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2024-07-30  1.0      fmarini Created
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
-- use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;
use surf.RocePkg.all;

entity RoceDmaDummyServer is

   generic (
      TPD_G       : time    := 1 ns;
      RST_ASYNC_G : boolean := false
      );
   port (
      RoceClk           : in  sl;
      RoceRst           : in  sl;
      dmaReadReqMaster  : in  RoceDmaReadReqMasterType;
      dmaReadReqSlave   : out RoceDmaReadReqSlaveType;
      dmaReadRespMaster : out RoceDmaReadRespMasterType;
      dmaReadRespSlave  : in  RoceDmaReadRespSlaveType
      );

end entity RoceDmaDummyServer;

architecture rtl of RoceDmaDummyServer is

   type RegState is (st0_idle,
                     st1_send_pkg);

   type RegType is record
      state        : RegState;
      reqLatched   : RoceDmaReadReqMasterType;
      first        : boolean;
      txRespMaster : RoceDmaReadRespMasterType;
      rxReqSlave   : RoceDmaReadReqSlaveType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      state        => st0_idle,
      reqLatched   => ROCE_DMA_READ_REQ_MASTER_INIT_C,
      first        => true,
      txRespMaster => ROCE_DMA_READ_RESP_MASTER_INIT_C,
      rxReqSlave   => ROCE_DMA_READ_REQ_SLAVE_INIT_C
      );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   constant AXI_STREAM_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 38,
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 0,
      TUSER_MODE_C  => TUSER_NORMAL_C
      );

   signal s_sAxisSlave       : AxiStreamSlaveType;
   signal s_mAxisMaster      : AxiStreamMasterType;
   signal s_dmaReadReqSlave  : RoceDmaReadReqSlaveType;
   signal s_dmaReadReqMaster : RoceDmaReadReqMasterType;

   signal s_len : natural;

begin  -- architecture rtl

   -----------------------------------------------------------------------------
   -- FIFO of requests
   -----------------------------------------------------------------------------
   AxiStreamFifoV2_1 : entity surf.AxiStreamFifoV2
      generic map (
         TPD_G               => TPD_G,
         GEN_SYNC_FIFO_G     => true,
         FIFO_ADDR_WIDTH_G   => 4,
         SLAVE_AXI_CONFIG_G  => AXI_STREAM_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXI_STREAM_CONFIG_C)
      port map (
         sAxisClk    => RoceClk,
         sAxisRst    => RoceRst,
         sAxisMaster => DmaReadReqToAxiStreamMaster(dmaReadReqMaster),
         sAxisSlave  => s_sAxisSlave,
         mAxisClk    => RoceClk,
         mAxisRst    => RoceRst,
         mAxisMaster => s_mAxisMaster,
         mAxisSlave  => DmaReadReqToAxiStreamSlave(s_dmaReadReqSlave)
         );

   dmaReadReqSlave    <= AxiStreamToDmaReadReqSlave(s_sAxisSlave);
   s_dmaReadReqMaster <= AxiStreamToDmaReadReqMaster(s_mAxisMaster);

   -----------------------------------------------------------------------------
   -- Comb & Seq
   -----------------------------------------------------------------------------
   comb : process (dmaReadRespSlave, r, s_dmaReadReqMaster) is
      variable v          : RegType;
      variable isFirst    : sl;
      variable isLast     : sl;
      variable byteEn     : slv(AXI_STREAM_MAX_TKEEP_WIDTH_C-1 downto 0);
      variable dataStream : slv(255 downto 0);
      variable len        : natural;
   begin  -- process comb
      -- Latch current value
      v := r;

      -- Init ready
      v.rxReqSlave.ready := '0';

      -- Choose ready source and clear valid
      if dmaReadRespSlave.ready = '1' then
         v.txRespMaster.valid := '0';
      end if;

      case r.state is
         -------------------------------------------------------------------------
         when st0_idle =>
            if s_dmaReadReqMaster.valid = '1' then
               v.rxReqSlave.ready := '1';
               v.reqLatched       := s_dmaReadReqMaster;
               v.state            := st1_send_pkg;
            end if;
         -----------------------------------------------------------------------
         when st1_send_pkg =>
            -- DataStream Fields
            if v.txRespMaster.valid = '0' then
               isFirst := '0';
               if r.first then
                  isFirst := '1';
                  v.first := false;
               end if;
               dataStream(dataStream'length-1 downto 64) := (others => '0');
               dataStream(63 downto 0)                   := r.reqLatched.startAddr;
               len                                       := to_integer(unsigned(r.reqLatched.len));
               if len < 33 then
                  isLast := '1';
                  byteEn := genTKeep(len);
               else
                  isLast := '0';
                  byteEn := (others => '1');
               end if;
               v.txRespMaster.dataStream := dataStream & byteEn(31 downto 0) & isFirst & isLast;
               v.txRespMaster.initiator  := r.reqLatched.initiator;
               v.txRespMaster.sQpn       := r.reqLatched.sQpn;
               v.txRespMaster.wrId       := r.reqLatched.wrId;
               v.txRespMaster.isRespErr  := '0';
               v.txRespMaster.valid      := '1';
               if isLast = '0' then
                  v.state          := st1_send_pkg;
                  v.reqLatched.len := r.reqLatched.len - 32;
               else
                  v.state := st0_idle;
                  v.first := true;
               end if;
            end if;
         -------------------------------------------------------------------------
         when others =>
            v := REG_INIT_C;
      end case;

      s_dmaReadReqSlave <= v.rxReqSlave;
      dmaReadRespMaster <= r.txRespMaster;

      rin   <= v;
      s_len <= len;

   end process comb;

   seq : process (RoceClk, RoceRst) is
   begin
      if (RST_ASYNC_G) and (RoceRst = '1') then
         r <= REG_INIT_C after TPD_G;
      elsif (rising_edge(RoceClk)) then
         if (RST_ASYNC_G = false and RoceRst = '1') then
            r <= REG_INIT_C after TPD_G;
         else
            r <= rin after TPD_G;
         end if;
      end if;
   end process seq;

end architecture rtl;
