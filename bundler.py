import os
import subprocess
import sys

with open("src/_bios.lua", "r") as f:
    bios = f.read()

mark = "--[[ XXX modules here ]]--"

modules = []

for file in os.listdir("src"):
    if not file.startswith("_") and file.endswith(".lua"):
        path = "src/" + file
        name = file[:-4]
        
        module = "[" + repr(name) + "] = (function(...)\n"
        
        with open(path, "r") as f:
            module += f.read() + "\n"
            
        module += "end)"
        modules.append(module)
        
bios = bios.replace(mark, mark + "\n{" + ", ".join(modules) + "}")

with open("output.lua", "w") as f:
    f.write(bios)
    
if not "dont_minify" in sys.argv:
    try:
        minified = subprocess.check_output(["luamin", "-f", "output.lua"], shell=True)
    except Exception as e:
        print("cannot minify", e)
    else:
        with open("output.lua", "wb") as f:
            f.write(minified)