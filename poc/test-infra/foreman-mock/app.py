#!/usr/bin/env python3
"""
Mock Foreman API server for testing Terraform provider
Responds to basic API calls with realistic data
"""

from flask import Flask, request, jsonify
from functools import wraps
import base64

app = Flask(__name__)

# In-memory storage
hosts = {}
hostgroups = {
    1: {"id": 1, "name": "Default", "architecture_id": 1, "operatingsystem_id": 1}
}
subnets = {}
partitiontables = {}
architectures = {
    1: {"id": 1, "name": "x86_64"}
}
operating_systems = {
    1: {"id": 1, "name": "Debian", "major": "12", "minor": "0", "title": "Debian 12.0"}
}

next_id = {"host": 1, "hostgroup": 2, "subnet": 1, "ptable": 1}

# Basic auth check
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or auth.username != 'admin' or auth.password != 'changeme123':
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated

@app.route('/api/status', methods=['GET'])
def status():
    return jsonify({
        "status": "ok",
        "version": "3.9.0",
        "api_version": 2
    })

@app.route('/api/architectures', methods=['GET'])
@app.route('/api/v2/architectures', methods=['GET'])
@require_auth
def get_architectures():
    # Handle search parameter (e.g., ?search=name="x86_64")
    search = request.args.get('search', '')
    results = list(architectures.values())

    if search:
        # Simple search parsing for name
        if 'name' in search:
            search_name = search.split('"')[1] if '"' in search else search.split('=')[1]
            results = [arch for arch in results if arch['name'] == search_name]

    # Return both formats for compatibility
    response = list(results) if results else results
    return jsonify(response)

@app.route('/api/operatingsystems', methods=['GET'])
@app.route('/api/v2/operatingsystems', methods=['GET'])
@require_auth
def get_operating_systems():
    # Handle search parameter
    search = request.args.get('search', '')
    results = list(operating_systems.values())

    if search:
        # Simple search parsing for name
        if 'name' in search or 'title' in search:
            search_term = search.split('"')[1] if '"' in search else search.split('=')[1].strip()
            results = [os for os in results if search_term.lower() in os['name'].lower() or search_term.lower() in os.get('title', '').lower()]

    # Return array directly for search results
    return jsonify(results)

@app.route('/api/hostgroups', methods=['GET', 'POST'])
@app.route('/api/v2/hostgroups', methods=['GET', 'POST'])
@require_auth
def hostgroups_api():
    if request.method == 'GET':
        return jsonify({
            "total": len(hostgroups),
            "results": list(hostgroups.values())
        })
    elif request.method == 'POST':
        data = request.json
        hg_id = next_id["hostgroup"]
        next_id["hostgroup"] += 1

        hostgroup = {
            "id": hg_id,
            "name": data.get("name", f"hostgroup-{hg_id}"),
            "architecture_id": data.get("architecture_id", 1),
            "operatingsystem_id": data.get("operatingsystem_id", 1),
            "subnet_id": data.get("subnet_id"),
            "ptable_id": data.get("ptable_id")
        }
        hostgroups[hg_id] = hostgroup
        return jsonify(hostgroup), 201

@app.route('/api/hostgroups/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@app.route('/api/v2/hostgroups/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@require_auth
def hostgroup_detail(id):
    if id not in hostgroups:
        return jsonify({"error": "Not found"}), 404

    if request.method == 'GET':
        return jsonify(hostgroups[id])
    elif request.method == 'PUT':
        data = request.json
        hostgroups[id].update(data)
        return jsonify(hostgroups[id])
    elif request.method == 'DELETE':
        del hostgroups[id]
        return '', 204

@app.route('/api/subnets', methods=['GET', 'POST'])
@app.route('/api/v2/subnets', methods=['GET', 'POST'])
@require_auth
def subnets_api():
    if request.method == 'GET':
        return jsonify({
            "total": len(subnets),
            "results": list(subnets.values())
        })
    elif request.method == 'POST':
        data = request.json
        subnet_id = next_id["subnet"]
        next_id["subnet"] += 1

        subnet = {
            "id": subnet_id,
            "name": data.get("name", f"subnet-{subnet_id}"),
            "network": data.get("network"),
            "mask": data.get("mask"),
            "gateway": data.get("gateway"),
            "dns_primary": data.get("dns_primary"),
            "dns_secondary": data.get("dns_secondary"),
            "from": data.get("from"),
            "to": data.get("to"),
            "vlanid": data.get("vlanid")
        }
        subnets[subnet_id] = subnet
        return jsonify(subnet), 201

@app.route('/api/subnets/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@app.route('/api/v2/subnets/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@require_auth
def subnet_detail(id):
    if id not in subnets:
        return jsonify({"error": "Not found"}), 404

    if request.method == 'GET':
        return jsonify(subnets[id])
    elif request.method == 'PUT':
        data = request.json
        subnets[id].update(data)
        return jsonify(subnets[id])
    elif request.method == 'DELETE':
        del subnets[id]
        return '', 204

@app.route('/api/ptables', methods=['GET', 'POST'])
@app.route('/api/v2/ptables', methods=['GET', 'POST'])
@require_auth
def ptables_api():
    if request.method == 'GET':
        return jsonify({
            "total": len(partitiontables),
            "results": list(partitiontables.values())
        })
    elif request.method == 'POST':
        data = request.json
        ptable_id = next_id["ptable"]
        next_id["ptable"] += 1

        ptable = {
            "id": ptable_id,
            "name": data.get("name", f"ptable-{ptable_id}"),
            "layout": data.get("layout", ""),
            "os_family": data.get("os_family", "Debian")
        }
        partitiontables[ptable_id] = ptable
        return jsonify(ptable), 201

@app.route('/api/ptables/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@app.route('/api/v2/ptables/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@require_auth
def ptable_detail(id):
    if id not in partitiontables:
        return jsonify({"error": "Not found"}), 404

    if request.method == 'GET':
        return jsonify(partitiontables[id])
    elif request.method == 'PUT':
        data = request.json
        partitiontables[id].update(data)
        return jsonify(partitiontables[id])
    elif request.method == 'DELETE':
        del partitiontables[id]
        return '', 204

@app.route('/api/hosts', methods=['GET', 'POST'])
@app.route('/api/v2/hosts', methods=['GET', 'POST'])
@require_auth
def hosts_api():
    if request.method == 'GET':
        return jsonify({
            "total": len(hosts),
            "results": list(hosts.values())
        })
    elif request.method == 'POST':
        data = request.json
        host_id = next_id["host"]
        next_id["host"] += 1

        host = {
            "id": host_id,
            "name": data.get("name", f"host-{host_id}"),
            "hostgroup_id": data.get("hostgroup_id"),
            "mac": data.get("mac"),
            "ip": data.get("ip"),
            "build": data.get("build", False),
            "enabled": True
        }
        hosts[host_id] = host
        return jsonify(host), 201

@app.route('/api/hosts/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@app.route('/api/v2/hosts/<int:id>', methods=['GET', 'PUT', 'DELETE'])
@require_auth
def host_detail(id):
    if id not in hosts:
        return jsonify({"error": "Not found"}), 404

    if request.method == 'GET':
        return jsonify(hosts[id])
    elif request.method == 'PUT':
        data = request.json
        hosts[id].update(data)
        return jsonify(hosts[id])
    elif request.method == 'DELETE':
        del hosts[id]
        return '', 204

@app.route('/api/hosts/<int:id>/power', methods=['PUT'])
@app.route('/api/v2/hosts/<int:id>/power', methods=['PUT'])
@require_auth
def host_power(id):
    if id not in hosts:
        return jsonify({"error": "Not found"}), 404

    data = request.json
    power_action = data.get("power_action", "status")

    return jsonify({
        "power": "on" if power_action == "on" else "off",
        "message": f"Power {power_action} executed"
    })

if __name__ == '__main__':
    print("Mock Foreman API Server")
    print("=======================")
    print("Listening on: http://0.0.0.0:3000")
    print("Credentials: admin / changeme123")
    print("")
    print("Endpoints:")
    print("  GET  /api/status")
    print("  GET  /api/v2/architectures")
    print("  GET  /api/v2/operatingsystems")
    print("  GET  /api/v2/hostgroups")
    print("  POST /api/v2/hostgroups")
    print("  GET  /api/v2/subnets")
    print("  POST /api/v2/subnets")
    print("  GET  /api/v2/ptables")
    print("  POST /api/v2/ptables")
    print("  GET  /api/v2/hosts")
    print("  POST /api/v2/hosts")
    print("")
    app.run(host='0.0.0.0', port=3000, debug=True)
