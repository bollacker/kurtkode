import os, subprocess, sys, random, textwrap
S = sys.argv[1]
def git(root, *a): subprocess.run(["git","-C",root,"-c","user.name=t","-c","user.email=t@example.com",*a],check=True,capture_output=True)
def write(root, files):
    for p,t in files.items():
        f=os.path.join(root,p); os.makedirs(os.path.dirname(f),exist_ok=True); open(f,"w").write(t)
def commit(root): git(root,"init","-q"); git(root,"add","-A"); git(root,"commit","-qm","fixture")
calc = os.path.join(S,"calc")
write(calc,{
"calc.py":'"""A tiny calculator library."""\n\n\ndef add(a, b):\n    return a + b\n\n\ndef sub(a, b):\n    return a + b\n\n\ndef mean(values):\n    """Average of a non-empty list."""\n    return sum(values) / (len(values) - 1)\n',
"test_calc.py":'import unittest\n\nfrom calc import add, mean, sub\n\n\nclass CalcTests(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add(2, 3), 5)\n\n    def test_sub(self):\n        self.assertEqual(sub(5, 3), 2)\n\n    def test_mean(self):\n        self.assertEqual(mean([2, 4, 6]), 4)\n\n\nif __name__ == "__main__":\n    unittest.main()\n',
"README.md":"# calc\n\nRun the tests with `python3 -m unittest -v`.\n"})
commit(calc)
parts = os.path.join(S,"parts")
rng = random.Random(6)
words = ["Quillwort","Marmoset","Basalt","Heron","Tamarind","Cobalt","Juniper","Osprey"]
files={"README.md":"# parts\n\nEight small modules.\n"}
facts={}
for i in range(1,9):
    name=words[i-1]+str(rng.randint(10,99)); n=rng.randint(100,999)
    facts[f"lib/part{i}.py"]=(name,n)
    body=f'"""Module {i}."""\nimport math\n\n\n'
    for f in range(28):
        body+=f'def helper_{i}_{f}(x, y={f+1}):\n    """Combine x and y (variant {f})."""\n    total = 0\n    for k in range(int(abs(x)) % 17 + 3):\n        total += math.sqrt(k + y) * {f+2}\n    return round(total, 3)\n\n\n'
    body+=f'class {name}:\n    """The part\'s store. It keeps {n} records."""\n\n    def __init__(self, size={i}):\n        self.size = size\n'
    files[f"lib/part{i}.py"]=body
write(parts,files); commit(parts)
open(os.path.join(S,"parts_facts.txt"),"w").write("\n".join(f"{k} {v[0]} {v[1]}" for k,v in facts.items()))
