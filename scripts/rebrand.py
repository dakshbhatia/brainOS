import os

def replace_in_file(file_path, search_replace):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        new_content = content
        for search, replace in search_replace.items():
            new_content = new_content.replace(search, replace)
        
        if new_content != content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"Updated: {file_path}")
    except Exception as e:
        # Skip binary files or files with encoding issues
        pass

search_replace = {
    "BrainOS": "BrainOS",
    "BrainOS": "BrainOS",
    "BRAINOS": "BRAINOS"
}

root_dir = "/Users/dakshbhatia/BrainOS"
exclude_dirs = {".git", ".github", "build", "DerivedData", "node_modules"}

for root, dirs, files in os.walk(root_dir):
    dirs[:] = [d for d in dirs if d not in exclude_dirs]
    for file in files:
        file_path = os.path.join(root, file)
        replace_in_file(file_path, search_replace)
