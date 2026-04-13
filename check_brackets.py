
def check_brackets(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    stack = []
    lines = content.split('\n')
    for i, line in enumerate(lines):
        line_num = i + 1
        for char in line:
            if char == '{':
                stack.append(('{', line_num))
            elif char == '}':
                if not stack:
                    print(f"Extra closing bracket at line {line_num}")
                else:
                    stack.pop()
    
    if stack:
        for char, line_num in stack:
            print(f"Unclosed bracket '{char}' from line {line_num}")
    else:
        print("All brackets are balanced.")

if __name__ == "__main__":
    import sys
    check_brackets(sys.argv[1])
