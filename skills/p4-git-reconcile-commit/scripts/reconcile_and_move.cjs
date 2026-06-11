const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function run(cmd) { try { return execSync(cmd, { stdio: 'pipe' }).toString().trim(); } catch (e) { return null; } }

const args = process.argv.slice(2);
const commitHash = args[0];
const targetCL = args[1];
const outputDirIndex = args.indexOf('--output-dir');
let outputDir = null;

if (outputDirIndex !== -1) {
    outputDir = args[outputDirIndex + 1];
}

if (!commitHash || !targetCL) {
    console.log("Usage: node reconcile_and_move.cjs <hash> <cl> [--output-dir <path>]");
    process.exit(1);
}

let report = `# P4-Git Reconcile Report\n\n`;
report += `Generated on: ${new Date().toLocaleString()}\n\n`;
report += `- **Git Commit Source:** \`${commitHash}\`\n`;
report += `- **P4 Target CL:** \`${targetCL}\` (Moving from \`default\`)\n\n`;

try {
    const gitFilesOutput = run(`git show --name-only --pretty=format: ${commitHash}`);
    if (!gitFilesOutput) throw new Error("Git commit not found or contains no changes.");
    const gitFiles = new Set(gitFilesOutput.split('\n').map(f => f.trim()).filter(f => f));
    
    const p4OpenedOutput = run("p4 opened -c default");
    const p4FilesRaw = p4OpenedOutput ? p4OpenedOutput.split('\n').filter(l => l.trim()) : [];
    
    const matches = [];
    const unmatchedInP4 = [];

    p4FilesRaw.forEach(line => {
        const depotPath = line.split('#')[0];
        const whereResult = run(`p4 where ${depotPath}`);
        if (!whereResult) return;
        const localPath = whereResult.split(/\s+/)[2];
        const root = run("git rev-parse --show-toplevel").replace(/\//g, '\\');
        const relativePath = localPath.replace(root + '\\', '').replace(/\\/g, '/');
        
        if (gitFiles.has(relativePath)) {
            matches.push(depotPath);
        } else {
            unmatchedInP4.push(depotPath);
        }
    });

    if (matches.length > 0) {
        console.log(`✅ Found ${matches.length} matching files.`);
        report += `### ✅ Matched & Ready to Move (${matches.length})\n`;
        report += `These files match the Git commit and will be moved to CL ${targetCL}.\n\n`;
        matches.forEach(m => report += `- \`${m}\` \n`);
        const cmd = `p4 reopen -c ${targetCL} ${matches.join(' ')}`;
        report += `\n**Command:** \`${cmd}\`\n\n`;
    } else {
        console.log("No matching files found.");
        report += `### ℹ️ No matching files found.\n\n`;
    }

    if (unmatchedInP4.length > 0) {
        console.log(`ℹ️ Found ${unmatchedInP4.length} unmatched files remaining in default.`);
        report += `### ⚠️ Unmatched Files in Default (${unmatchedInP4.length})\n`;
        report += `These files are in P4 \`default\` but NOT in the Git commit. **Consider reverting these if they are unnecessary.**\n\n`;
        unmatchedInP4.forEach(f => report += `- \`${f}\` \n`);
        report += `\n**Quick Revert Command (Careful!):**\n\`\`\`bash\np4 revert ${unmatchedInP4.join(' ')}\n\`\`\`\n`;
    }

} catch (error) {
    console.error(`Error: ${error.message}`);
    report += `### ❌ Error during analysis\n${error.message}\n`;
}

if (outputDir) {
    if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });
    const summaryPath = path.join(outputDir, `P4_Reconcile_Report_${Date.now()}.md`);
    fs.writeFileSync(summaryPath, report);
    console.log(`\nSummary report exported to: ${summaryPath}`);
}
