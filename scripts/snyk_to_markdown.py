#!/usr/bin/env python3
import json
import sys
import os

def generate_markdown(sarif_path):
    if not os.path.exists(sarif_path):
        print(f"File not found: {sarif_path}")
        return
    
    with open(sarif_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            print(f"Error decoding JSON from {sarif_path}")
            return
            
    results = []
    for run in data.get('runs', []):
        rules = {rule['id']: rule for rule in run.get('tool', {}).get('driver', {}).get('rules', [])}
        for res in run.get('results', []):
            rule_id = res.get('ruleId', 'Unknown')
            message = res.get('message', {}).get('text', 'No message')
            level = res.get('level', 'warning')
            
            uri = 'Unknown'
            locations = res.get('locations', [])
            if locations:
                uri = locations[0].get('physicalLocation', {}).get('artifactLocation', {}).get('uri', 'Unknown')
                
            rule_info = rules.get(rule_id, {})
            severity = rule_info.get('properties', {}).get('security-severity', 'Unknown')
            
            results.append({
                'ruleId': rule_id,
                'level': level,
                'severity': severity,
                'message': message.split('\n')[0],
                'uri': uri
            })

    if not results:
        return "## Snyk Security Scan\n\n✅ No vulnerabilities found!\n"

    md = "## Snyk Security Scan\n\n"
    md += f"**Total Vulnerabilities:** {len(results)}\n\n"
    md += "| Severity | Rule | File | Message |\n"
    md += "| --- | --- | --- | --- |\n"
    
    for r in results:
        sev_icon = "🔴" if r['level'] == 'error' else "🟠"
        md += f"| {sev_icon} {r['level'].capitalize()} | {r['ruleId']} | `{r['uri']}` | {r['message']} |\n"

    return md

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 snyk_to_markdown.py <path_to_sarif>")
        sys.exit(1)
        
    sarif_file = sys.argv[1]
    md_output = generate_markdown(sarif_file)
    if md_output:
        step_summary_file = os.environ.get('GITHUB_STEP_SUMMARY')
        if step_summary_file:
            with open(step_summary_file, 'a') as f:
                f.write(md_output + '\n')
        else:
            print(md_output)
