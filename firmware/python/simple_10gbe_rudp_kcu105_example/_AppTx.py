#-----------------------------------------------------------------------------
# This file is part of the 'Simple-10GbE-RUDP-KCU105-Example'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'Simple-10GbE-RUDP-KCU105-Example', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import pyrogue as pr

class AppTx0(pr.Device):
    def __init__( self,**kwargs):
        super().__init__(**kwargs)

        self.add(pr.RemoteVariable(
            name         = 'FrameSize',
            description  = 'Number of words to send per frame (Units of 64-bit words, zero inclusive)',
            offset       = 0x000,
            bitSize      = 32,
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'SendFrame',
            description  = 'Write Only for sending burst of frames (Units of frames)',
            offset       = 0x004,
            bitSize      = 32,
            mode         = 'WO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'FrameCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x008,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'WordCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x00C,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'ContinuousMode',
            description  = 'Bursting Continuously Flag',
            offset       = 0x010,
            bitSize      = 1,
            mode         = 'RW',
            base         = pr.Bool,
        ))

class AppTx1(pr.Device):
    def __init__( self,**kwargs):
        super().__init__(**kwargs)

        self.add(pr.RemoteVariable(
            name         = 'FrameSize',
            description  = 'Number of words to send per frame (Units of 64-bit words, zero inclusive)',
            offset       = 0x000,
            bitSize      = 32,
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'SendFrame',
            description  = 'Write Only for sending burst of frames (Units of frames)',
            offset       = 0x004,
            bitSize      = 32,
            mode         = 'WO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'FrameCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x008,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'WordCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x00C,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'ContinuousMode',
            description  = 'Bursting Continuously Flag',
            offset       = 0x010,
            bitSize      = 1,
            mode         = 'RW',
            base         = pr.Bool,
        ))

class AppTx2(pr.Device):
    def __init__( self,**kwargs):
        super().__init__(**kwargs)

        self.add(pr.RemoteVariable(
            name         = 'FrameSize',
            description  = 'Number of words to send per frame (Units of 64-bit words, zero inclusive)',
            offset       = 0x000,
            bitSize      = 32,
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'SendFrame',
            description  = 'Write Only for sending burst of frames (Units of frames)',
            offset       = 0x004,
            bitSize      = 32,
            mode         = 'WO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'FrameCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x008,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'WordCnt',
            description  = 'Read Only for monitoring bursting status',
            offset       = 0x00C,
            bitSize      = 32,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'ContinuousMode',
            description  = 'Bursting Continuously Flag',
            offset       = 0x010,
            bitSize      = 1,
            mode         = 'RW',
            base         = pr.Bool,
        ))
