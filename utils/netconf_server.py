#!/usr/bin/env python3

import logging
import sys

from netconf import nsmap_update, server
import netconf.util as ncutil

MODEL_NS = "urn:my-urn:my-model"
nsmap_update({'pfx': MODEL_NS})

class MyServer (object):
    def __init__ (self, user, pw):
        controller = server.SSHUserPassController(username=user, password=pw)
        self.server = server.NetconfSSHServer(server_ctl=controller, server_methods=self, debug=True)

    def nc_append_capabilities(self, caps):
        ncutil.subelm(caps, "capability").text = MODEL_NS

    def rpc_my_cool_rpc (self, session, rpc, *params):
        data = ncutil.elm("data")
        data.append(ncutil.leaf_elm("pfx:result", "RPC result string"))
        return data

    def rpc_my_cool_rpc2 (self, session, rpc, *params):
        data = ncutil.elm("data")
        data.append(ncutil.leaf_elm("pfx:result", "BAR"))
        return data

# ...
root = logging.getLogger()
root.setLevel(logging.DEBUG)

handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
root.addHandler(handler)

server = MyServer("myuser", "mysecert")
server.server.join()
