import json
import os
import sys

def exec_mxs(cmd, pipe_name=r'\\.\pipe\3dsmax-mcp-pid-10268'):
    with open(pipe_name, 'r+b', buffering=0) as f:
        req = json.dumps({'type': 'maxscript', 'command': cmd, 'requestId': 'test'}) + '\n'
        f.write(req.encode('utf-8'))
        resp = f.readline().decode('utf-8')
        return json.loads(resp)

def run_tests():
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ms_path = os.path.join(script_dir, 'RM_ImportClean.ms').replace('\\', '/')
    
    print(f"Loading script: {ms_path}")
    res = exec_mxs(f'filein "{ms_path}"')
    print("Filein response:", res)
    
    if not res.get('success'):
        print("ERROR loading script:", res.get('error'))
        return False
        
    # Check dialog open status
    res = exec_mxs('RM_IC_MainRol != undefined and RM_IC_MainRol.open')
    print("RM_IC_MainRol is open:", res)
    
    # Check language
    res = exec_mxs('rm_ic_lang as string')
    print("Current language:", res)
    
    # Test rollouts count and captions
    res = exec_mxs('RM_IC_MainRol.sub_holder.rollouts.count')
    print("Sub-rollouts count:", res)
    
    # Check rollout titles
    res = exec_mxs('#(RM_IC_MainRol.sub_holder.rollouts[1].title, RM_IC_MainRol.sub_holder.rollouts[2].title, RM_IC_MainRol.sub_holder.rollouts[3].title)')
    print("Rollout titles (RU):", res)
    
    # Simulate Language Toggle to English
    print("\n--- Testing Language Toggle to EN ---")
    res = exec_mxs('RM_IC_MainRol.btn_lang.pressed()')
    print("btn_lang pressed result:", res)
    
    res = exec_mxs('rm_ic_lang as string')
    print("Language after toggle:", res)
    
    res = exec_mxs('#(RM_IC_MainRol.sub_holder.rollouts[1].title, RM_IC_MainRol.sub_holder.rollouts[2].title, RM_IC_MainRol.sub_holder.rollouts[3].title)')
    print("Rollout titles (EN):", res)
    
    res = exec_mxs('RM_IC_MainRol.btn_lang.text')
    print("Language button text (should be RU when in EN mode):", res)
    
    # Simulate Language Toggle back to Russian
    print("\n--- Testing Language Toggle back to RU ---")
    res = exec_mxs('RM_IC_MainRol.btn_lang.pressed()')
    print("btn_lang pressed result:", res)
    
    res = exec_mxs('rm_ic_lang as string')
    print("Language after toggle back:", res)
    
    res = exec_mxs('#(RM_IC_MainRol.sub_holder.rollouts[1].title, RM_IC_MainRol.sub_holder.rollouts[2].title, RM_IC_MainRol.sub_holder.rollouts[3].title)')
    print("Rollout titles (RU):", res)
    
    # Run auto-fit height diagnostic probe
    print("\n--- Running probe_ui_height.ms ---")
    probe_path = os.path.join(script_dir, 'tools', 'probe_ui_height.ms').replace('\\', '/')
    res = exec_mxs(f'filein "{probe_path}"')
    print("probe_ui_height result:\n", res.get('result', ''))
    
    return True

if __name__ == '__main__':
    run_tests()
