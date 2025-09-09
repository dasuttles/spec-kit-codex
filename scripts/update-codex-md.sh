#!/usr/bin/env bash
# Incrementally update CODEX.md based on new feature plan
# Modeled after the Claude script and update-agent-context.sh

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
FEATURE_DIR="$REPO_ROOT/specs/$CURRENT_BRANCH"
NEW_PLAN="$FEATURE_DIR/plan.md"
TARGET_FILE="$REPO_ROOT/CODEX.md"

if [ ! -f "$NEW_PLAN" ]; then
    echo "ERROR: No plan.md found at $NEW_PLAN"
    exit 1
fi

echo "=== Updating Codex CLI context file for feature $CURRENT_BRANCH ==="

# Extract tech from new plan
NEW_LANG=$(grep "^**Language/Version**: " "$NEW_PLAN" 2>/dev/null | head -1 | sed 's/^**Language\/Version**: //' | grep -v "NEEDS CLARIFICATION" || echo "")
NEW_FRAMEWORK=$(grep "^**Primary Dependencies**: " "$NEW_PLAN" 2>/dev/null | head -1 | sed 's/^**Primary Dependencies**: //' | grep -v "NEEDS CLARIFICATION" || echo "")
NEW_TESTING=$(grep "^**Testing**: " "$NEW_PLAN" 2>/dev/null | head -1 | sed 's/^**Testing**: //' | grep -v "NEEDS CLARIFICATION" || echo "")
NEW_DB=$(grep "^**Storage**: " "$NEW_PLAN" 2>/dev/null | head -1 | sed 's/^**Storage**: //' | grep -v "N/A" | grep -v "NEEDS CLARIFICATION" || echo "")
NEW_PROJECT_TYPE=$(grep "^**Project Type**: " "$NEW_PLAN" 2>/dev/null | head -1 | sed 's/^**Project Type**: //' || echo "")

update_agent_file() {
    local target_file="$1"
    local agent_name="$2"

    echo "Updating $agent_name context file: $target_file"

    local temp_file=$(mktemp)

    if [ ! -f "$target_file" ]; then
        echo "Creating new $agent_name context file..."
        if [ -f "$REPO_ROOT/templates/agent-file-template.md" ]; then
            cp "$REPO_ROOT/templates/agent-file-template.md" "$temp_file"
        else
            echo "ERROR: Template not found at $REPO_ROOT/templates/agent-file-template.md"
            return 1
        fi

        sed -i.bak "s/\[PROJECT NAME\]/$(basename $REPO_ROOT)/" "$temp_file"
        sed -i.bak "s/\[DATE\]/$(date +%Y-%m-%d)/" "$temp_file"
        sed -i.bak "s/\[EXTRACTED FROM ALL PLAN.MD FILES\]/- $NEW_LANG + $NEW_FRAMEWORK ($CURRENT_BRANCH)/" "$temp_file"

        if [[ "$NEW_PROJECT_TYPE" == *"web"* ]]; then
            sed -i.bak "s|\[ACTUAL STRUCTURE FROM PLANS\]|backend/\nfrontend/\ntests/|" "$temp_file"
        else
            sed -i.bak "s|\[ACTUAL STRUCTURE FROM PLANS\]|src/\ntests/|" "$temp_file"
        fi

        if [[ "$NEW_LANG" == *"Python"* ]]; then
            COMMANDS="cd src && pytest && ruff check ."
        elif [[ "$NEW_LANG" == *"Rust"* ]]; then
            COMMANDS="cargo test && cargo clippy"
        elif [[ "$NEW_LANG" == *"JavaScript"* ]] || [[ "$NEW_LANG" == *"TypeScript"* ]]; then
            COMMANDS="npm test && npm run lint"
        else
            COMMANDS="# Add commands for $NEW_LANG"
        fi
        sed -i.bak "s|\[ONLY COMMANDS FOR ACTIVE TECHNOLOGIES\]|$COMMANDS|" "$temp_file"

        sed -i.bak "s|\[LANGUAGE-SPECIFIC, ONLY FOR LANGUAGES IN USE\]|$NEW_LANG: Follow standard conventions|" "$temp_file"
        sed -i.bak "s|\[LAST 3 FEATURES AND WHAT THEY ADDED\]|- $CURRENT_BRANCH: Added $NEW_LANG + $NEW_FRAMEWORK|" "$temp_file"

        rm "$temp_file.bak"
    else
        echo "Updating existing $agent_name context file..."

        local manual_start=$(grep -n "<!-- MANUAL ADDITIONS START -->" "$target_file" | cut -d: -f1)
        local manual_end=$(grep -n "<!-- MANUAL ADDITIONS END -->" "$target_file" | cut -d: -f1)
        if [ ! -z "$manual_start" ] && [ ! -z "$manual_end" ]; then
            sed -n "${manual_start},${manual_end}p" "$target_file" > /tmp/manual_additions.txt
        fi

        python3 - << EOF
import re
from datetime import datetime

with open("$target_file", 'r') as f:
    content = f.read()

tech_section = re.search(r'## Active Technologies\n(.*?)\n\n', content, re.DOTALL)
if tech_section:
    existing_tech = tech_section.group(1)
    new_additions = []
    if "$NEW_LANG" and "$NEW_LANG" not in existing_tech:
        new_additions.append(f"- $NEW_LANG + $NEW_FRAMEWORK ($CURRENT_BRANCH)")
    if "$NEW_DB" and "$NEW_DB" not in existing_tech and "$NEW_DB" != "N/A":
        new_additions.append(f"- $NEW_DB ($CURRENT_BRANCH)")
    if new_additions:
        updated_tech = existing_tech + "\n" + "\n".join(new_additions)
        content = content.replace(tech_section.group(0), f"## Active Technologies\n{updated_tech}\n\n")

if "$NEW_PROJECT_TYPE" == "web" and "frontend/" not in content:
    struct_section = re.search(r'## Project Structure\n\`\`\`\n(.*?)\n\`\`\`', content, re.DOTALL)
    if struct_section:
        updated_struct = struct_section.group(1) + "\nfrontend/src/      # Web UI"
        content = re.sub(r'(## Project Structure\n\`\`\`\n).*?(\n\`\`\`)', f'\\1{updated_struct}\\2', content, flags=re.DOTALL)

if "$NEW_LANG" and f"# {NEW_LANG}" not in content:
    commands_section = re.search(r'## Commands\n\`\`\`bash\n(.*?)\n\`\`\`', content, re.DOTALL)
    if not commands_section:
        commands_section = re.search(r'## Commands\n(.*?)\n\n', content, re.DOTALL)
    if commands_section:
        new_commands = commands_section.group(1)
        if "Python" in "$NEW_LANG":
            new_commands += "\ncd src && pytest && ruff check ."
        elif "Rust" in "$NEW_LANG":
            new_commands += "\ncargo test && cargo clippy"
        elif "JavaScript" in "$NEW_LANG" or "TypeScript" in "$NEW_LANG":
            new_commands += "\nnpm test && npm run lint"
        if "```bash" in content:
            content = re.sub(r'(## Commands\n\`\`\`bash\n).*?(\n\`\`\`)', f'\\1{new_commands}\\2', content, flags=re.DOTALL)
        else:
            content = re.sub(r'(## Commands\n).*?(\n\n)', f'\\1{new_commands}\\2', content, flags=re.DOTALL)

changes_section = re.search(r'## Recent Changes\n(.*?)(\n\n|$)', content, re.DOTALL)
if changes_section:
    changes = changes_section.group(1).strip().split('\n')
    changes.insert(0, f"- $CURRENT_BRANCH: Added $NEW_LANG + $NEW_FRAMEWORK")
    changes = changes[:3]
    content = re.sub(r'(## Recent Changes\n).*?(\n\n|$)', f'\\1{chr(10).join(changes)}\\2', content, flags=re.DOTALL)

content = re.sub(r'Last updated: \d{4}-\d{2}-\d{2}', f'Last updated: {datetime.now().strftime("%Y-%m-%d")}', content)

with open("$temp_file", 'w') as f:
    f.write(content)
EOF

        if [ -f /tmp/manual_additions.txt ]; then
            sed -i.bak '/<!-- MANUAL ADDITIONS START -->/,/<!-- MANUAL ADDITIONS END -->/d' "$temp_file"
            cat /tmp/manual_additions.txt >> "$temp_file"
            rm /tmp/manual_additions.txt "$temp_file.bak"
        fi
    fi

    mv "$temp_file" "$target_file"
    echo "✓ $agent_name context file updated successfully"
}

update_agent_file "$TARGET_FILE" "Codex CLI"

echo ""
echo "Summary of changes:"
if [ ! -z "$NEW_LANG" ]; then
    echo "- Added language: $NEW_LANG"
fi
if [ ! -z "$NEW_FRAMEWORK" ]; then
    echo "- Added framework: $NEW_FRAMEWORK"
fi
if [ ! -z "$NEW_DB" ] && [ "$NEW_DB" != "N/A" ]; then
    echo "- Added database: $NEW_DB"
fi

echo ""
echo "Usage: $0"
echo "  Updates or creates CODEX.md from the latest plan.md"

