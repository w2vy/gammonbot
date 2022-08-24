#!/usr/bin/python3
'''This module is a single file that supports the loading of secrets into a Flux Node'''
import json
import sys
import requests
from fluxvault import FluxAgent
from datetime import datetime

VAULT_NAME = "home.moulton.us"                    # EDIT ME
FILE_DIR = "/home/tom/Docker/gbot-docker/test/"   # EDIT ME
VAULT_PORT = 34321                                # EDIT ME
APP_NAME = "gammonbot"                            # EDIT ME
VERBOSE = False

def logmsg(msg):
    dt = datetime.now()
    now = dt.strftime("%b-%d-%Y %H:%M:%S ")
    return now+msg

def print_log(ip, mylog):
    print(" ")
    print(ip + " Min " + str(mylog['min']) + " Max " + str(mylog['max']) + " Avg " + str(mylog['avg']))
    for line in mylog['log']:
        print(line)

def dump_report():
    try:
        with open(FILE_DIR+"node_log.json") as file:
            data = file.read()
        node_log = json.loads(data)
    except:
        print("Error opening data file " + FILE_DIR+"node_log.json")
        return
    for ip in node_log.keys():
        print_log(ip, node_log[ip])

class MyFluxAgent(FluxAgent):
    '''User class to allow easy configuration, see EDIT ME above'''
    def __init__(self) -> None:
        super().__init__()
        self.vault_name = VAULT_NAME
        self.file_dir = FILE_DIR
        self.vault_port = VAULT_PORT
        self.verbose = VERBOSE

def node_vault():
    '''Vault runs this to poll every Flux node running their app'''
    url = "https://api.runonflux.io/apps/location/" + APP_NAME
    req = requests.get(url)
    # Get the list of nodes where our app is deplolyed
    if req.status_code == 200:
        values = json.loads(req.text)
        if values["status"] == "success":
            # json looks good and status correct, iterate through node list
            nodes = values["data"]
            try:
                with open(FILE_DIR+"node_log.json") as file:
                    data = file.read()
                node_log = json.loads(data)
            except:
                node_log = {}

            for ip in node_log.keys():
                node_log[ip]['active'] = 0

            for node in nodes:
                if node['ip'] in node_log:
                    mylog = node_log[node['ip']]
                    mylog['active'] = 1
                else:
                    if VERBOSE:
                        print("New Node " + node['ip'])
                    msg = logmsg("New Instance " + node['ip'])
                    mylog = { 'log': [msg], 'min':999999999, 'max':0, 'avg':0, 'active':1, 'reported':0 }
                start = datetime.now()
                agent = MyFluxAgent() # Each connection to a node get a fresh agent
                ipadr = node['ip'].split(':')[0]
                if VERBOSE:
                    print(node['name'], ipadr)
                agent.node_vault_ip(ipadr)
                dt = datetime.now() - start
                ms = round(dt.microseconds/1000)+dt.seconds*1000
                if VERBOSE:
                    print(ms, " ms")
                    print(node['name'], ipadr, agent.result)
                if 'min' not in mylog:
                    mylog['min'] = mylog['max'] = mylog['avg'] = 0
                if ms < mylog['min']:
                    mylog['min'] = ms
                if ms > mylog['max']:
                    mylog['max'] = ms
                if mylog['avg'] == 0:
                    mylog['avg'] = ms
                else:
                    # Smoothed average 7/8 of average plus 1/8 new sample
                    mylog['avg'] = round(mylog['avg'] - (mylog['avg']/8) + (ms/8))
                mylog['log'] += agent.log
                node_log[node['ip']] = mylog
            if VERBOSE:
                print("************************ REPORT *****************************")
            pop_nodes = []
            for ip in node_log.keys():
                if node_log[ip]['active'] == 0:
                    msg = logmsg("Node removed " + ip)
                    node_log[ip]['log'] += [msg]
                    print_log(ip, node_log[ip])
                    pop_nodes += [ip]
                else:
                    if len(node_log[ip]['log']) > node_log[ip]['reported']:
                        print_log(ip, node_log[ip])
                        node_log[ip]['reported'] = len(node_log[ip]['log'])
            for ip in pop_nodes:
                node_log.pop(ip, None)

            try:
                with open(FILE_DIR+"node_log.json", 'w') as file:
                    data = file.write(json.dumps(node_log))
            except:
                print("Save log failed")

        else:
            print("Error", req.text)
    else:
        print("Error", url, "Status", req.status_code)

if __name__ == "__main__":
    if len(sys.argv) == 1:
        node_vault()
        sys.exit(0)
    if sys.argv[1].lower() == "--ip":
        if len(sys.argv) > 2:
            ipaddr = sys.argv[2]
            one_node = MyFluxAgent()
            one_node.node_vault_ip(ipaddr)
            print(ipaddr, one_node.result)
            sys.exit(0)
        else:
            print("Missing Node IP Address: --ip ipaddress")
    if sys.argv[1].lower() == "--dump":
        dump_report()
        sys.exit(0)
    print("Incorrect arguments:")
    print("With no arguments all nodes running ", APP_NAME, " will be polled")
    print("If you specify '--ip ipaddress' then that ipaddress will be polled")
    sys.exit(1)
