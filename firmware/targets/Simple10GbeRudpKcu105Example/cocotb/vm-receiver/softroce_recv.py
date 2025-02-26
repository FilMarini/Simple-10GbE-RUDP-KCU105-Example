import sys
sys.path.insert(1, '/home/vagrant/tools/rdma-core/build/python')
import time
import random
import sys
import pyverbs.enums as e
import pyverbs.device as d
from pyverbs.pd import PD
from pyverbs.qp import QPCap, QPInitAttr, QP, QPAttr
from pyverbs.addr import GlobalRoute, AH, AHAttr, GID
from pyverbs.mr import MR
from pyverbs.cq import CQ
import pyverbs.wr as pwr

def decode(s, encoding="ascii", errors="ignore"):
    return s.decode(encoding=encoding, errors=errors)

def random_data(size):
    return bytearray(random.getrandbits(8) for _ in range(size))

MR_SIZE = 2048

rdma_info_dict = {
    "lid": 0,
    "qpn": 0,
    "psn": 0,
    "gid": GID()
}

my_dest = rdma_info_dict.copy()
rem_dest = rdma_info_dict.copy()


def main():
    dev_list = d.get_device_list()
    if not dev_list:
        print("No RDMA devices found.", file=sys.stderr)
        sys.exit(1)

    dev_name = dev_list[0].name.decode()
    print(f"Using RDMA device: {dev_name}")

    # Open Context
    ctx = d.Context(name=dev_name)

    # Memory region
    pd = PD(ctx)
    mr_access = e.IBV_ACCESS_REMOTE_WRITE | e.IBV_ACCESS_LOCAL_WRITE
    mr = MR(pd, access = mr_access, length = MR_SIZE)

    # Completion queue
    cq = CQ(ctx, cqe = 2)

    # Queue pair
    cap = QPCap(max_send_wr = 1, max_recv_wr = 1, max_send_sge = 1, max_recv_sge = 1)
    qp_init_attr = QPInitAttr(qp_type=e.IBV_QPT_RC, cap=cap, scq=cq, rcq=cq, qp_context = ctx)
    qp = QP(pd, init_attr = qp_init_attr)

    # Reset2Init
    qp_attr = QPAttr()
    qp_attr.port_num = 1
    qp_attr.pkey_index = 0
    qp_attr.qp_access_flags = e.IBV_ACCESS_REMOTE_WRITE | e.IBV_ACCESS_LOCAL_WRITE
    qp.to_init(qp_attr)

    # Get my information
    port_attr = ctx.query_port(1)
    my_dest["lid"] = port_attr.lid
    gid = ctx.query_gid(port_num = 1, index = 1)
    my_dest["gid"] = gid
    my_dest["qpn"] = qp.qp_num
    my_dest["psn"] = 18695
    for key, value in my_dest.items():
        print(key, ":", value)
    print("rkey: ", mr.rkey)
    print("raddr: ", mr.buf)

    # Get server information
    rem_dest["lid"] = int(input("rem lid: "))
    rem_dest["qpn"] = int(input("rem qpn: "))
    rem_dest["psn"] = int(input("rem psn: "))
    rem_gid_str = str(input("rem gid: "))
    rem_gid = GID()
    rem_gid.gid = rem_gid_str
    rem_dest["gid"] = rem_gid

    # Init2RTR
    qp_attr.path_mtu = e.IBV_MTU_256
    qp_attr.dest_qp_num = rem_dest["qpn"]
    qp_attr.rq_psn = rem_dest["psn"]
    qp_attr.max_dest_rd_atomic = 1
    qp_attr.min_rnr_timer = 12
    grh= GlobalRoute(dgid = rem_dest["gid"], sgid_index = 1)
    grh.hop_limit = 1
    ah_attr = AHAttr(is_global = 1, gr = grh)
    ah_attr.dlid = rem_dest["lid"]
    ah_attr.sl = 0
    ah_attr.src_path_bits = 0
    ah_attr.port_num = 1
    qp_attr.ah_attr = ah_attr
    qp.to_rtr(qp_attr)

    """
    # RTR2RTS
    qp_attr.timeout = 14
    qp_attr.retry_cnt = 7
    qp_attr.rnr_retry = 7
    qp_attr.sq_psn = my_dest["psn"]
    qp_attr.max_rd_atomic = 1
    qp.to_rts(qp_attr)
    """

    input("Press enter when send done..")
    mrdata = mr.read(MR_SIZE, 0)
    #print("Data received: ", decode(mrdata))
    print("Data received: ", mrdata)

    # Cleanup
    mr.close()
    qp.close()
    cq.close()
    pd.close()
    ctx.close()

if __name__ == '__main__':
    main()
