import json

def exec_mxs(cmd, pipe_name=r'\\.\pipe\3dsmax-mcp-pid-10268'):
    with open(pipe_name, 'r+b', buffering=0) as f:
        req = json.dumps({'type': 'maxscript', 'command': cmd, 'requestId': 'test'}) + '\n'
        f.write(req.encode('utf-8'))
        resp = f.readline().decode('utf-8')
        return json.loads(resp)

def run():
    t1 = """
    (
        local b = Box width:100 length:100 height:50 widthsegs:4 lengthsegs:4 heightsegs:2
        convertToMesh b
        local ok = rm_ic_convert b maxSize:4 keepConvex:true requirePlanar:true planarTol:1.0 keepMidEdge:true
        local isPoly = (classOf b.baseObject == Editable_Poly)
        local numF = polyop.getNumFaces b
        delete b
        "ok=" + ok as string + " isPoly=" + isPoly as string + " faces=" + numF as string
    )
    """
    print("1. Convert to Poly:", exec_mxs(t1)['result'])

    t2 = """
    (
        local p = Plane length:100 width:100 lengthsegs:10 widthsegs:10
        convertToPoly p
        local v0 = polyop.getNumVerts p, f0 = polyop.getNumFaces p
        local eR = rm_ic_coplanarEdges p faceTol:1.0 keepMat:true keepSG:true keepUV:false
        local vR = rm_ic_collinearVerts p vertTol:1.0
        local v1 = polyop.getNumVerts p, f1 = polyop.getNumFaces p
        delete p
        "v: " + v0 as string + "->" + v1 as string + " (del " + vR as string + ") | f: " + f0 as string + "->" + f1 as string + " (edges del " + eR as string + ")"
    )
    """
    print("2. Clean Geometry:", exec_mxs(t2)['result'])

    t3 = """
    (
        local c1 = Box width:10 length:10 height:10 pos:[0,0,0]
        convertToPoly c1
        local c2 = Box width:10 length:10 height:10 pos:[30,0,0]
        convertToPoly c2
        polyop.attach c1 c2
        local c3 = Box width:10 length:10 height:10 pos:[60,0,0]
        convertToPoly c3
        polyop.attach c1 c3
        local s1 = Sphere radius:5 pos:[0,40,0] segs:8
        convertToPoly s1
        polyop.attach c1 s1
        local s2 = Sphere radius:5 pos:[30,40,0] segs:8
        convertToPoly s2
        polyop.attach c1 s2
        
        local groups = rm_ic_analyze c1 false 0.5
        local nE = rm_ic_ef_elems.count
        local nG = groups.count
        local g1Count = groups[1][2].count
        local g2Count = groups[2][2].count
        delete c1
        "Elements: " + nE as string + ", Groups: " + nG as string + " (Group 1 count: " + g1Count as string + ", Group 2 count: " + g2Count as string + ")"
    )
    """
    print("3. Duplicate Elements:", exec_mxs(t3)['result'])

if __name__ == '__main__':
    run()
