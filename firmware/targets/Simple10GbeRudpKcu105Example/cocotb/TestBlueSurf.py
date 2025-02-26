import os
import random
import logging
import json
import sys
import time
import math

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import cocotb_test.simulator
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
from cocotbext.eth import XgmiiSource, XgmiiSink, XgmiiFrame
from bitstring import Bits, BitArray, BitStream, pack
#from cocotb.queue import Queue

from scapy.all import *
from scapy.contrib.roce import *

from BSVSettings import *
from TestUtils import *
from BusStructs import *
from DmaPyServer import *

# Settings
# Number of tests
CASES_NUM = 5
# MetaData settings
PD_NUM = 1
QP_NUM = 1
MR_NUM = 1
RDMA_PAYLOAD_TOTAL_LEN = 7168

def is_root():
    return os.geteuid() == 0

class BlueSurfTester:
    def __init__(
            self,
            dut,
            casesNum = 1,
            pdNum = 2,
            qpNum = 1,
            mrNum = 1,
            rem_qpn = [],
            rem_psn = [],
            rem_rkey = [],
            rem_addr = [],
            local_psn = [],
            check_ack = False,
            interface = 'vboxnet0',
    ):
        self.dut = dut
        self.log = logging.getLogger("BlueSurf")
        self.log.setLevel(logging.DEBUG)
        # Sim settings
        self.casesNum = casesNum
        self.pdNum = pdNum
        self.qpNum = qpNum
        self.mrNum = mrNum
        # Input values
        self.sqPsnVec = []
        self.rqPsnVec = []
        self.dqpnVec = []
        self.rKeyVec = []
        self.rAddrVec = []
        if len(rem_qpn) < self.qpNum:
            for caseIdx in range(self.qpNum):
                self.dqpnVec.append(random.getrandbits(QPA_DQPN_B))
        else:
            self.dqpnVec = rem_qpn
        if len(rem_psn) < self.qpNum:
            for caseIdx in range(self.qpNum):
                self.rqPsnVec.append(random.getrandbits(QPA_RQPSN_B))
        else:
            self.rqPsnVec = rem_psn
        if len(local_psn) < self.qpNum:
            for caseIdx in range(self.qpNum):
                self.sqPsnVec.append(random.getrandbits(QPA_SQPSN_B))
        else:
            self.sqPsnVec = local_psn
        if len(rem_rkey) < self.qpNum:
            for caseIdx in range(self.qpNum):
                self.rKeyVec.append(random.getrandbits(WR_RKEY_B))
        else:
            self.rKeyVec = rem_rkey
        if len(rem_addr) < self.qpNum:
            for caseIdx in range(self.qpNum):
                self.rAddrVec.append(random.getrandbits(WR_RADDR_B))
        else:
            self.rAddrVec = rem_addr
        self.checkAck = check_ack
        self.interface = interface
        # Used signals
        self.pdHandlerVec4Req = []
        self.lKeyVec4Write = []
        self.qpnVec = []
        self.qpnVec4RTS = []
        self.sqpnVec4Write = []
        self.qpiTypeVec = []
        self.wrIdVec = []
        self.dmaRCRespsQ = cocotb.queue.Queue(maxsize=qpNum)
        # Clock
        self.clock = self.dut.clk
        # Reset
        self.reset = self.dut.rst
        # PhyReady
        self.phy_ready = self.dut.phyReady
        # WorkReqAxisSlave
        self.work_req_src = WorkReqSource(
            WorkReqBus.from_prefix(dut, "s_work_req"),
            self.clock,
            self.reset,
        )
        # WorkCompRQAxisMaster
        """
        self.work_comp_rq_sink = WorkCompSink(
            WorkCompBus.from_prefix(dut, "m_work_comp_rq"),
            self.clock,
            self.reset,
        )
        """
        # WorkCompSQAxisMaster
        self.work_comp_sq_sink = WorkCompSink(
            WorkCompBus.from_prefix(dut, "m_work_comp_sq"),
            self.clock,
            self.reset,
        )
        #MetaDataAxisMaster
        self.meta_data_sink = MetaDataSink(
            MetaDataBus.from_prefix(dut, "m_meta_data"),
            self.clock,
            self.reset,
        )
        # MetaDataAxisSlave
        self.meta_data_src = MetaDataSource(
            MetaDataBus.from_prefix(dut, "s_meta_data"),
            self.clock,
            self.reset,
        )
        # DmaReadCltAxisMaster
        self.dma_read_clt_sink = DmaReadCltReqSink(
            DmaReadCltReqBus.from_prefix(dut, "m_dma_read"),
            self.clock,
            self.reset,
        )
        # DmaReadCltAxisSlave
        self.dma_read_clt_src = DmaReadCltRespSource(
            DmaReadCltRespBus.from_prefix(dut, "s_dma_read"),
            self.clock,
            self.reset,
        )
        # UdpAxiStreamMaster
        """
        self.udp_stream_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "M_AXIS_IBMAC"),
            self.clock,
            self.reset,
        )
        self.udp_stream_sink.log.setLevel(logging.WARNING)
        """
        # UdpAxiStreamMasterLoopback
        """
        self.data_stream_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "M_AXIS_OBSERVER"),
            self.clock,
            self.reset,
        )
        self.data_stream_sink.log.setLevel(logging.WARNING)
        """
        #XGMII TX Sniffer
        self.xgmii_sink = XgmiiSink(
            dut.xgmiiTxD,
            dut.xgmiiTxC,
            self.clock,
            self.reset,
        )
        self.xgmii_sink.log.setLevel(logging.WARNING)
        #XGMII RX Sniffer
        self.xgmii_rx_sink = XgmiiSink(
            dut.xgmiiRxDout,
            dut.xgmiiRxCout,
            self.clock,
            self.reset,
        )
        self.xgmii_rx_sink.log.setLevel(logging.WARNING)
        #XGMII RX Source
        self.xgmii_rx_source = XgmiiSource(
            dut.xgmiiRxDin,
            dut.xgmiiRxCin,
            self.clock,
            self.reset,
        )
        self.xgmii_rx_source.log.setLevel(logging.WARNING)
        self.xgmiiRxFlow = dut.xgmiiRxFlow

    async def gen_clock(self):
        await cocotb.start(Clock(self.clock, 10, "ns").start())
        self.log.info("Start generating clock")

    async def gen_reset(self):
        self.reset.value = 1
        self.phy_ready.value = 0
        self.xgmiiRxFlow.value = 0
        for _ in range(20):
            await RisingEdge(self.clock)
        self.reset.value = 0
        for _ in range(20):
            await RisingEdge(self.clock)
        self.phy_ready.value = 1
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)

    async def req_alloc_pd(self):
        for caseIdx in range(self.pdNum):
            allocOrNot = BitStream(uint = 1, length = PD_ALLOC_OR_NOT_B)
            pdKey = BitStream(uint = random.getrandbits(PD_KEY_B), length = PD_KEY_B)
            pdReq = reqPd(allocOrNot = allocOrNot, pdKey = pdKey)
            metaData = MetaDataTransaction()
            metaData.tdata = pdReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_alloc_pd(self):
        for caseIdx in range(self.pdNum):
            dut_alloc_pd_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_pd_resp.tdata.integer, length = META_DATA_BITS)
            pdResp = respPd(metaRespBus)
            assert pdResp.busType.uint == METADATA_PD_T, f'Bus type should be {METADATA_PD_T}, instead decoded {pdResp.busType.uint}'
            assert pdResp.successOrNot, "Creation of PD not successfull!"
            self.log.info(f'pdHandler for PD {caseIdx}: {pdResp.pdHandler.hex}, {pdResp.pdHandler.bin}')
            self.log.debug(f'pdKey for PD {caseIdx}: {pdResp.pdKey.bin}')
            self.pdHandlerVec4Req.append(pdResp.pdHandler.uint)

    async def req_alloc_mr(self):
        for caseIdx in range(self.mrNum):
            pdHandler = self.pdHandlerVec4Req[caseIdx % self.pdNum]

            allocOrNot = BitStream(uint = 1, length = MR_ALLOC_OR_NOT_B)
            mrLAddr = BitStream(uint = DEFAULT_ADDR, length = MR_LADDR_B)
            mrLen = BitStream(uint = DEFAULT_LEN, length = MR_LEN_B)
            mrAccFlags = BitStream(uint = ACC_PERM, length = MR_ACCFLAGS_B)
            mrPdHandler = BitStream(uint = pdHandler, length = MR_PDHANDLER_B)
            mrLKeyPart = BitStream(uint = random.getrandbits(MR_LKEYPART_B), length = MR_LKEYPART_B)
            mrRKeyPart = BitStream(uint = random.getrandbits(MR_RKEYPART_B), length = MR_RKEYPART_B)
            lKeyOrNot = BitStream(uint = 0, length = 1)
            mrReq = reqMr(allocOrNot = allocOrNot, mrLAddr = mrLAddr, mrLen = mrLen, mrAccFlags = mrAccFlags,
                          mrPdHandler = mrPdHandler, mrLKeyPart = mrLKeyPart, mrRkeyPart = mrRKeyPart,
                          lKeyOrNot = lKeyOrNot)
            metaData = MetaDataTransaction()
            metaData.tdata = mrReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_alloc_mr(self):
        for caseIdx in range(self.mrNum):
            dut_alloc_mr_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_mr_resp.tdata.integer, length = META_DATA_BITS)
            mrResp = respMr(metaRespBus)
            assert mrResp.busType.uint == METADATA_MR_T, f'Bus type should be {METADATA_MR_T}, instead decoded {mrResp.busType.uint}'
            assert mrResp.successOrNot, "Creation of MR not successfull!"
            self.log.debug(f'lKey for write for MR {caseIdx}: {mrResp.lKey.hex}')
            self.lKeyVec4Write.append(mrResp.lKey.uint)

    async def req_create_qp(self):
        for caseIdx in range(self.qpNum):
            pdHandler = self.pdHandlerVec4Req[caseIdx % self.pdNum]

            qpReqType = BitStream(uint = REQ_QP_CREATE, length = QP_REQTYPE_B)
            qpPdHandler = BitStream(uint = pdHandler, length = QP_PDHANDLER_B)
            qpiType = BitStream(uint = IBV_QPT_RC, length = QPI_TYPE_B)
            qpiSqSigAll = BitStream(uint = 0, length = QPI_SQSIGALL_B)
            qpReq = reqQp(pdHandler = qpPdHandler, qpReqType = qpReqType, qpiType = qpiType, qpiSqSigAll = qpiSqSigAll)

            metaData = MetaDataTransaction()
            metaData.tdata = qpReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_create_qp(self):
        for caseIdx in range(self.qpNum):
            dut_alloc_qp_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_qp_resp.tdata.integer, length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "Creation of QP not successfull!"
            self.log.debug(f'QP number for QP {caseIdx}: {qpResp.qpn.hex}')
            self.qpnVec.append(qpResp.qpn.uint)
            self.qpiTypeVec.append(qpResp.qpiType.uint)

    async def req_init_qp(self):
        for caseIdx in range(self.qpNum):
            qpInitAttrMask = IBV_QP_STATE + IBV_QP_PKEY_INDEX + IBV_QP_ACCESS_FLAGS

            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpn = BitStream(uint = self.qpnVec[caseIdx], length = QP_QPN_B)
            qpAttrMask = BitStream(uint = qpInitAttrMask, length = QP_ATTRMASK_B)
            qpaPKey = BS(uint = 0xFFFF, length = (QPA_PKEY_B))
            qpReq  = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask, qpaPKey = qpaPKey)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_1024, qpState = IBV_QPS_INIT)
            metaData = MetaDataTransaction()
            metaData.tdata = qpReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_init_qp(self):
        for caseIdx in range(self.qpNum):
            dut_alloc_qp_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_qp_resp.tdata.integer, length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to init state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_INIT, f'QP state not in init state, instead decoded {qpResp.qpaQpState.uint}'
            self.log.info(f'QP {caseIdx} state to Init')

    async def req_rtr_qp(self):
        for caseIdx in range(self.qpNum):
            qpInit2RtrAttrMask = (IBV_QP_STATE + IBV_QP_PATH_MTU + IBV_QP_DEST_QPN +
                                  IBV_QP_RQ_PSN + IBV_QP_MAX_DEST_RD_ATOMIC + IBV_QP_MIN_RNR_TIMER)
            dqpn_value = self.dqpnVec[caseIdx]
            rqPsn_value = self.rqPsnVec[caseIdx]

            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpn = BitStream(uint = self.qpnVec[caseIdx], length = QP_QPN_B)
            qpAttrMask = BitStream(uint = qpInit2RtrAttrMask, length = QP_ATTRMASK_B)
            qpReq = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_1024, dqpn_value = dqpn_value, qpState = IBV_QPS_RTR, rqPsn = rqPsn_value)
            metaData = MetaDataTransaction()
            metaData.tdata = qpReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_rtr_qp(self):
        for caseIdx in range(self.qpNum):
            dut_alloc_qp_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_qp_resp.tdata.integer, length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to RTR state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_RTR, f'QP state not in RTR state, instead decoded {qpResp.qpaQpState.uint}'
            self.log.info(f'QP {caseIdx} state to RTR with qpn: {qpResp.qpn.hex} and dqpn: {qpResp.qpaDqpn.hex}')
            self.qpnVec4RTS.append(qpResp.qpn.uint)
            self.sqpnVec4Write.append([qpResp.qpn.uint, qpResp.qpaDqpn.uint])

    async def req_rts_qp(self):
        for caseIdx in range(self.qpNum):
            qpRtr2RtsAttrMask = (IBV_QP_STATE + IBV_QP_SQ_PSN + IBV_QP_TIMEOUT
                                  + IBV_QP_RETRY_CNT + IBV_QP_RNR_RETRY + IBV_QP_MAX_QP_RD_ATOMIC)
            dqpn_value = self.dqpnVec[caseIdx]
            sqPsn_value = self.sqPsnVec[caseIdx]

            qpn = BitStream(uint = self.qpnVec4RTS[caseIdx], length = QP_QPN_B)
            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpAttrMask = BitStream(uint = qpRtr2RtsAttrMask, length = QP_ATTRMASK_B)
            qpReq = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_1024, qpState = IBV_QPS_RTS, sqPsn = sqPsn_value)
            metaData = MetaDataTransaction()
            metaData.tdata = qpReq.getBusValue()
            await self.meta_data_src.send(metaData)

    async def resp_rts_qp(self):
        for caseIdx in range(self.qpNum):
            dut_alloc_qp_resp = await self.meta_data_sink.recv()
            metaRespBus = BitStream(uint = dut_alloc_qp_resp.tdata.integer, length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to RTS state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_RTS, f'QP state not in RTS state, instead decoded {qpResp.qpaQpState.uint}'
            self.log.info(f'QP {caseIdx} state to RTS')

    async def issue_work_req(self):
        for caseIdx in range(self.qpNum):
            for caseNum in range(self.casesNum):
                qpiType = self.qpiTypeVec[caseIdx]
                sqpn, dqpn = self.sqpnVec4Write[caseIdx]
                lKey = self.lKeyVec4Write[caseIdx]
                rKey = self.rKeyVec[caseIdx]
                lAddr = DEFAULT_ADDR
                rAddr = self.rAddrVec[caseIdx] + (caseNum * RDMA_PAYLOAD_TOTAL_LEN)
                wrReq = self.gen_wr(qpiType = qpiType,
                                    wrOpCode = IBV_WR_RDMA_WRITE,
                                    needResp = True,
                                    sqpn = sqpn,
                                    dqpn = dqpn,
                                    lKey = lKey,
                                    rKey = rKey,
                                    lAddr = lAddr,
                                    rAddr = rAddr,
                                    )
                self.wrIdVec.append(wrReq.id)
                await self.work_req_src.send(wrReq)
                self.log.info(f'WR {caseNum} with ID {self.wrIdVec[caseNum]} has been issued!')

    def gen_wr(self, qpiType, wrOpCode, needResp, sqpn, dqpn, lKey, rKey, lAddr, rAddr):
        isAtomicWR = False
        wrReq = WorkReqTransaction()
        wrReq.id = random.getrandbits(WR_ID_B)
        wrReq.opCode = wrOpCode
        wrReq.flags = IBV_SEND_SIGNALED if needResp else IBV_SEND_NO_FLAGS
        wrReq.raddr = rAddr
        wrReq.rkey = rKey
        wrReq.len = RDMA_PAYLOAD_TOTAL_LEN # different if atomic WR
        wrReq.laddr = lAddr
        wrReq.lkey = lKey
        wrReq.sqpn = sqpn
        wrReq.solicited = 0
        wrReq.comp = tagInvalid()
        wrReq.swap = tagInvalid()
        wrReq.imm_dt = tagInvalid()
        wrReq.rkey_to_inv = tagInvalid()
        wrReq.srqn = tagValid(dqpn, WR_M_SRQN_B) if qpiType == IBV_QPT_XRC_SEND else tagInvalid()
        wrReq.dqpn = tagValid(dqpn, WR_M_DQPN_B) if qpiType == IBV_QPT_UD else tagInvalid()
        wrReq.qkey = tagInvalid()
        return wrReq

    async def check_work_comp(self):
        for caseIdx in range(self.qpNum):
            for caseNum in range(self.casesNum):
                work_comp = await self.work_comp_sq_sink.recv()
                assert work_comp.flags.integer == 0, f'WorkComp flags should be 0, got {work_comp.flags.integer} instead'
                assert self.wrIdVec[caseNum] == work_comp.id.integer, f'WrID mismatch in work completion. wrID completed is {work_comp.id.integer} should be {self.wrIdVec[caseNum]}'
                assert work_comp.status.integer == 0, f'Work completion not successful. Status is {workCompStatus[work_comp.status.integer]}'
                self.log.info(f'WR {caseNum} with ID {work_comp.id.integer} has completed')

    async def get_dma_read_req(self):
        while True:
            dut_dma_req = await self.dma_read_clt_sink.recv()
            await self.dmaRCRespsQ.put(dmaPyServer(initiator = dut_dma_req.initiator.integer,
                                                   sqpn = dut_dma_req.sqpn.integer,
                                                   startAddr = dut_dma_req.start_addr.integer,
                                                   pktLen = dut_dma_req.len.integer,
                                                   wrId = dut_dma_req.wr_id.integer,
                                                   ))
            self.log.debug(f'Received DMA req: wrId -> {hex(dut_dma_req.wr_id.integer)}, len -> {hex(dut_dma_req.len.integer)}')

    async def get_dma_read_resp(self):
        while True:
            dmaRCRespPkts = await self.dmaRCRespsQ.get()
            self.log.debug(f'Sending DMA resp: wrId -> {hex(dmaRCRespPkts[0].wr_id)}')
            for dmaRCRespPkt in dmaRCRespPkts:
                await self.dma_read_clt_src.send(dmaRCRespPkt)

    async def xgmii_sendp(self):
        pkt_idx = 0
        while True:
            data = await self.xgmii_sink.recv()
            packet = Ether(data.get_payload())
            self.log.debug(f'Sending packet {pkt_idx} from XGMII')
            if is_root():
                if self.checkAck:
                    ackSniffer = AsyncSniffer(
                        iface = self.interface,
                        filter = "udp dst port 4791 and ip dst 192.168.56.01",
                        count = 1,
                    )
                    ackSniffer.start()
                    time.sleep(0.6)
                sendp(packet, iface = self.interface)
                if self.checkAck:
                    time.sleep(0.6)
                    try:
                        ackSniffer.stop()
                    except:
                        pass
                    if len(ackSniffer.results) == 1:
                        self.log.debug(f'Scapy received respose for packet {pkt_idx}')
                        self.xgmiiRxFlow.value = 1
                        await RisingEdge(self.clock)
                        ackRaw = raw(ackSniffer.results[0])
                        xgmiiAck = XgmiiFrame.from_payload(ackRaw)
                        await self.xgmii_rx_source.send(xgmiiAck)
            pkt_idx = pkt_idx + 1

    async def check_work_comp(self):
        for caseNum in range(self.casesNum):
            work_comp = await self.work_comp_sq_sink.recv()
            assert work_comp.flags.integer == 0, f'WorkComp flags should be 0, got {work_comp.flags.integer} instead'
            assert self.wrIdVec[caseNum] == work_comp.id.integer, f'WrID mismatch in work completion. wrID completed is {work_comp.id.integer} should be {self.wrIdVec[caseNum]}'
            assert work_comp.status.integer == 0, f'Work completion not successful. Status is {workCompStatus[work_comp.status.integer]}'
            self.log.info(f'WR {caseNum} with ID {work_comp.id.integer} has completed')

@cocotb.test(timeout_time=1000000000, timeout_unit="ns")
async def runBlueSurfTester(dut):
    rem_qpn = [int(x) for x in (os.getenv("REM_QPN")).split(',')]
    rem_psn = [int(x) for x in (os.getenv("REM_PSN")).split(',')]
    rem_rkey = [int(x) for x in (os.getenv("REM_RKEY")).split(',')]
    rem_addr = [int(x) for x in (os.getenv("REM_ADDR")).split(',')]
    local_psn = [int(x) for x in (os.getenv("LOCAL_PSN")).split(',')]
    check_ack = os.getenv("CHECK_ACK")
    interface = os.getenv("INTERFACE")
    tester = BlueSurfTester(
        dut,
        casesNum = CASES_NUM,
        pdNum = PD_NUM,
        qpNum = QP_NUM,
        mrNum = MR_NUM,
        rem_qpn = rem_qpn,
        rem_psn = rem_psn,
        rem_rkey = rem_rkey,
        rem_addr = rem_addr,
        local_psn = local_psn,
        check_ack = check_ack,
        interface = interface,
    )
    await tester.gen_clock()
    await tester.gen_reset()
    tester.log.info("Starting DmaPyServer")
    get_dma_req_thread = cocotb.start_soon(tester.get_dma_read_req())
    get_dma_resp_thread = cocotb.start_soon(tester.get_dma_read_resp())
    tester.log.info("Start testing!")
    # Choose between sending packets from Udp engine or XGMII
    #sendp_thread = cocotb.start_soon(tester.sendp())
    xgmii_sendp_thread = cocotb.start_soon(tester.xgmii_sendp())
    await RisingEdge(tester.clock)
    alloc_pd_thread = cocotb.start_soon(tester.req_alloc_pd())
    check_alloc_pd_thread = cocotb.start_soon(tester.resp_alloc_pd())
    await check_alloc_pd_thread
    alloc_mr_thread = cocotb.start_soon(tester.req_alloc_mr())
    check_alloc_mr_thread = cocotb.start_soon(tester.resp_alloc_mr())
    await check_alloc_mr_thread
    create_qp_thread = cocotb.start_soon(tester.req_create_qp())
    check_create_qp_thread = cocotb.start_soon(tester.resp_create_qp())
    await check_create_qp_thread
    init_qp_thread = cocotb.start_soon(tester.req_init_qp())
    check_init_qp_thread = cocotb.start_soon(tester.resp_init_qp())
    await check_init_qp_thread
    rtr_qp_thread = cocotb.start_soon(tester.req_rtr_qp())
    check_rtr_qp_thread = cocotb.start_soon(tester.resp_rtr_qp())
    await check_rtr_qp_thread
    rts_qp_thread = cocotb.start_soon(tester.req_rts_qp())
    check_rts_qp_thread = cocotb.start_soon(tester.resp_rts_qp())
    await check_rts_qp_thread
    # Wait some time for link to be up
    for i in range(200):
        await RisingEdge(tester.clock)
    issue_wr_thread = cocotb.start_soon(tester.issue_work_req())
    await issue_wr_thread
    if is_root():
        check_work_comp_thread = cocotb.start_soon(tester.check_work_comp())
        await check_work_comp_thread
    for i in range(600):
        await RisingEdge(tester.clock)


