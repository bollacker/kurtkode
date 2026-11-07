import glob,os,json,sys,time
t=float(sys.argv[1]); text=sys.argv[2]; end=time.time()+float(sys.argv[3])
while time.time()<end:
    for f in glob.glob(os.path.expanduser("~/Library/Application Support/kurtkode/sessions/_chats/*.jsonl")):
        if os.path.getmtime(f)<t: continue
        s=open(f).read()
        if text not in s: continue
        for l in s.splitlines():
            m=json.loads(l).get('message')
            if m and m['role']=='assistant' and (m.get('meta') or {}).get('stopReason'): print(f.split('/')[-1], len(m['content'])); sys.exit(0)
    time.sleep(2)
print("timeout"); sys.exit(1)
