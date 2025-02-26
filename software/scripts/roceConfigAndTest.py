import setupLibPaths
import sys
import logging
import time
import argparse
import pyrogue as pr

import socket

from bitstring import Bits, BitArray, BitStream, pack
from BusStructs import *
from TestUtils import *

def sendMeta(Req):
    ## Latch config
    roceEngine.MetaDataTx.set(Req.getBusValue())
    ## Send config
    roceEngine.SendMetaData.set(0x0)
    roceEngine.SendMetaData.set(0x1)
    roceEngine.SendMetaData.set(0x0)


if __name__ == "__main__":

    # Convert str to bool
    argBool = lambda s: s.lower() in ['true', 't', 'yes', '1']

    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Add arguments
    parser.add_argument(
        "--addr",
        type     = str,
        required = False,
        default  = 'localhost',
        help     = "ZMQ server address",
    )

    parser.add_argument(
        "--port",
        type     = int,
        required = False,
        default  = 9099,
        help     = "ZMQ server port",
    )

    parser.add_argument(
        "--sim",
        action   = 'store_true',
        help     = "ZMQ server port",
    )

    parser.add_argument(
        "--dqpn",
        required = False,
        default  = 17,
        help     = "Remote QPN",
    )

    parser.add_argument(
        "--rqpsn",
        required = False,
        default  = 18695,
        help     = "Remote PSN",
    )

    parser.add_argument(
        "--sqpsn",
        required = False,
        default  = 18697,
        help     = "Local PSN",
    )

    parser.add_argument(
        "--cases",
        required = False,
        default  = 1,
        type     = int,
        help     = "Number of packets to send",
    )

    parser.add_argument(
        "--payload",
        required = False,
        default  = 300,
        type     = int,
        help     = "Packets payload",
    )

    parser.add_argument(
        "--init",
        required = False,
        action   = 'store_true',
        help     = "Init Roce engine",
    )

    # Get the arguments
    args = parser.parse_args()

    #################################################################
    with pr.interfaces.VirtualClient(
            addr = args.addr,
            port = args.port,
    ) as client:

        # Use a TCP/IP socket to connect to the server and exchange information
        client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client_socket.connect(('127.0.0.1', 9999))  # Replace with server IP
        # Receive the server's QP number and RKey
        data = client_socket.recv(1024).decode()
        server_qp_num, server_rkey, server_raddr = map(int, data.split(','))

        # Close the connection
        client_socket.close()


        # Set base
        root = client.root
        roceEngine = root.Core.RoceEngine

        # Set IP
        root.Core.UdpEngine.ClientRemotePort[0].set(4791)
        root.Core.UdpEngine.ClientRemoteIp[0].set("192.168.2.202")

        # Set logger
        log = logging.getLogger('configRoce')
        log.setLevel(logging.DEBUG)

        # Reset counters
        log.info('Resetting counters..')
        root.App.RoceChecker.ResetCounters.set(0)
        root.App.RoceChecker.ResetCounters.set(1)
        root.App.RoceChecker.ResetCounters.set(0)

        input("Press Enter to continue..")

        # Needed variables
        pdHandler4Req = 0
        lKey4Write = 0
        qpNum = 0
        qpiType = 0
        qpNum4RTS = 0
        sqpn4Write = []

        if args.init:
            # Req alloc PD
            ## Create bus
            allocOrNot = BitStream(uint = 1, length = PD_ALLOC_OR_NOT_B)
            pdKey = BitStream(uint = random.getrandbits(PD_KEY_B), length = PD_KEY_B)
            pdReq = reqPd(allocOrNot = allocOrNot, pdKey = pdKey)
            ## Send config
            sendMeta(pdReq)

            # Resp alloc PD
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            pdResp = respPd(metaRespBus)
            assert pdResp.busType.uint == METADATA_PD_T, f'Bus type should be {METADATA_PD_T}, instead decoded {pdResp.busType.uint}'
            assert pdResp.successOrNot, "Creation of PD not successfull!"
            pdHandler4Req = pdResp.pdHandler.uint
            log.info('PD alloc sucessful')
            log.debug(f'pdHandler from PD alloc resp is {hex(pdHandler4Req)}')

            # Req alloc MR
            allocOrNot = BitStream(uint = 1, length = PD_ALLOC_OR_NOT_B)
            mrLAddr = BitStream(uint = DEFAULT_ADDR, length = MR_LADDR_B)
            mrLen = BitStream(uint = DEFAULT_LEN, length = MR_LEN_B)
            mrAccFlags = BitStream(uint = ACC_PERM, length = MR_ACCFLAGS_B)
            mrPdHandler = BitStream(uint = pdHandler4Req, length = MR_PDHANDLER_B)
            mrLKeyPart = BitStream(uint = random.getrandbits(MR_LKEYPART_B), length = MR_LKEYPART_B)
            mrRKeyPart = BitStream(uint = random.getrandbits(MR_RKEYPART_B), length = MR_RKEYPART_B)
            lKeyOrNot = BitStream(uint = 0, length = 1)
            mrReq = reqMr(allocOrNot = allocOrNot, mrLAddr = mrLAddr, mrLen = mrLen, mrAccFlags = mrAccFlags,
                          mrPdHandler = mrPdHandler, mrLKeyPart = mrLKeyPart, mrRkeyPart = mrRKeyPart,
                          lKeyOrNot = lKeyOrNot)
            ## Send config
            sendMeta(mrReq)

            # Resp alloc MR
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            mrResp = respMr(metaRespBus)
            assert mrResp.busType.uint == METADATA_MR_T, f'Bus type should be {METADATA_MR_T}, instead decoded {mrResp.busType.uint}'
            assert mrResp.successOrNot, "Creation of MR not successfull!"
            lKey4Write = mrResp.lKey.uint
            log.info('MR alloc sucessful')
            log.debug(f'lKey from MR alloc resp is {hex(lKey4Write)}')

            # Req create QP
            qpReqType = BitStream(uint = REQ_QP_CREATE, length = QP_REQTYPE_B)
            qpPdHandler = BitStream(uint = pdHandler4Req, length = QP_PDHANDLER_B)
            qpiType = BitStream(uint = IBV_QPT_RC, length = QPI_TYPE_B)
            qpiSqSigAll = BitStream(uint = 0, length = QPI_SQSIGALL_B)
            qpReq = reqQp(pdHandler = qpPdHandler, qpReqType = qpReqType, qpiType = qpiType, qpiSqSigAll = qpiSqSigAll)
            ## Send config
            sendMeta(qpReq)

            # Resp create QP
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "Creation of QP not successfull!"
            log.debug(f'QP number: {qpResp.qpn.hex}')
            qpNum = qpResp.qpn.uint
            qpiType = qpResp.qpiType.uint
            log.info('QP creation sucessful')

            # Req init QP
            qpInitAttrMask = IBV_QP_STATE + IBV_QP_PKEY_INDEX + IBV_QP_ACCESS_FLAGS
            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpn = BitStream(uint = qpNum, length = QP_QPN_B)
            qpAttrMask = BitStream(uint = qpInitAttrMask, length = QP_ATTRMASK_B)
            qpaPKey = BS(uint = 0xFFFF, length = (QPA_PKEY_B))
            qpReq  = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask, qpaPKey = qpaPKey)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_4096, qpState = IBV_QPS_INIT)
            ## Send config
            sendMeta(qpReq)

            # Resp init QP
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to init state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_INIT, f'QP state not in init state, instead decoded {qpResp.qpaQpState.uint}'
            log.info('QP state to init')

            # Req RTR QP
            qpInit2RtrAttrMask = (IBV_QP_STATE + IBV_QP_PATH_MTU + IBV_QP_DEST_QPN +
                                  IBV_QP_RQ_PSN + IBV_QP_MAX_DEST_RD_ATOMIC + IBV_QP_MIN_RNR_TIMER)
            #dqpn_value = args.dqpn
            dqpn_value = server_qp_num
            rqPsn_value = args.rqpsn

            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpn = BitStream(uint = qpNum, length = QP_QPN_B)
            qpAttrMask = BitStream(uint = qpInit2RtrAttrMask, length = QP_ATTRMASK_B)
            qpReq = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_4096, dqpn_value = dqpn_value, qpState = IBV_QPS_RTR, rqPsn = rqPsn_value)
            ## Send config
            sendMeta(qpReq)

            # Resp RTR QP
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to RTR state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_RTR, f'QP state not in RTR state, instead decoded {qpResp.qpaQpState.uint}'
            log.info(f'QP state to RTR with qpn: {qpResp.qpn.hex} and dqpn: {qpResp.qpaDqpn.hex}')
            qpn4RTS = qpResp.qpn.uint
            sqpn4Write = [qpResp.qpn.uint, qpResp.qpaDqpn.uint]

            # Req RTS QP
            qpRtr2RtsAttrMask = (IBV_QP_STATE + IBV_QP_SQ_PSN + IBV_QP_TIMEOUT
                                 + IBV_QP_RETRY_CNT + IBV_QP_RNR_RETRY + IBV_QP_MAX_QP_RD_ATOMIC)
            sqPsn_value = args.sqpsn
            qpn = BitStream(uint = qpn4RTS, length = QP_QPN_B)
            qpReqType = BitStream(uint = REQ_QP_MODIFY, length = QP_REQTYPE_B)
            qpAttrMask = BitStream(uint = qpRtr2RtsAttrMask, length = QP_ATTRMASK_B)
            qpReq = reqQp(qpReqType = qpReqType, qpn = qpn, qpAttrMask = qpAttrMask)
            qpReq.mkSimQpAttr(pmtu_value = IBV_MTU_4096, qpState = IBV_QPS_RTS, sqPsn = sqPsn_value)
            ## Send config
            sendMeta(qpReq)

            # Resp RTS QP
            while (roceEngine.RecvMetaData.get() != 0x1):
                time.sleep(0.2)
            metaRespBus = BitStream(uint = roceEngine.MetaDataRx.get(), length = META_DATA_BITS)
            qpResp = respQp(metaRespBus)
            assert qpResp.busType.uint == METADATA_QP_T, f'Bus type should be {METADATA_QP_T}, instead decoded {qpResp.busType.uint}'
            assert qpResp.successOrNot, "QP to RTS state not successfull!"
            assert qpResp.qpaQpState.uint == IBV_QPS_RTS, f'QP state not in RTS state, instead decoded {qpResp.qpaQpState.uint}'
            log.info('QP state to RTS')

        # Set dispatcher
        root.App.RoceDispatcher.Len.set(args.payload)
        root.App.RoceDispatcher.DispatchCounter.set(args.cases)
        root.App.RoceDispatcher.RKey.set(server_rkey)
        root.App.RoceDispatcher.RemAddr.set(server_raddr)
        if args.init:
            root.App.RoceDispatcher.SQpn.set(qpn4RTS)
            root.App.RoceDispatcher.LKey.set(lKey4Write)

        # Dispatch
        log.info(f'Dispatching {args.cases} packets of {args.payload} bytes..')
        root.App.RoceDispatcher.StartDispatching.set(0)
        root.App.RoceDispatcher.StartDispatching.set(1)
        root.App.RoceDispatcher.StartDispatching.set(0)

        # Check
        time.sleep(1)
        log.info(f'Correctly received {root.App.RoceChecker.SuccessCounter.get()} packets!')


