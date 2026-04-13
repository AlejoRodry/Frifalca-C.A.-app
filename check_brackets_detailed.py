
def check_brackets(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    stack = []
    lines = content.split('\n')
    for i, line in enumerate(lines):
        line_num = i + 1
        for j, char in enumerate(line):
            if char == '{':
                stack.append(('{', line_num, j, line))
            elif char == '}':
                if not stack:
                    print(f"Extra closing bracket at line {line_num}: {line.strip()}")
                else:
                    stack.pop()
    
    if stack:
        print(f"Total unclosed: {len(stack)}")
        for char, line_num, j, line in stack:
            print(f"Line {line_num}: {line.strip()}")

if __name__ == "__main__":
    import sys
    check_brackets(sys.argv[1])
