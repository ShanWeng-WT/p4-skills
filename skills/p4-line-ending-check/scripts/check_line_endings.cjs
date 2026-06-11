const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/**
 * Calculates a hash of the content after normalizing line endings (removing all \r).
 */
function getNormalizedHash(content) {
    const normalized = content.toString().replace(/\r/g, '');
    return crypto.createHash('md5').update(normalized).digest('hex');
}

function checkFile(depotPath, fileType) {
    try {
        if (!fileType.includes('text') && !fileType.includes('unicode') && !fileType.includes('utf')) {
            return { status: 'skipped', message: `Skipped: File type is ${fileType}` };
        }

        const localPathOutput = execSync(`p4 where ${depotPath}`).toString();
        const localFilePath = localPathOutput.split(/\s+/)[2];
        
        if (!fs.existsSync(localFilePath)) {
            return { status: 'error', message: 'Local file not found' };
        }
        const localContent = fs.readFileSync(localFilePath);
        const serverContent = execSync(`p4 print -q ${depotPath}#have`, { maxBuffer: 100 * 1024 * 1024 });

        const localHash = getNormalizedHash(localContent);
        const serverHash = getNormalizedHash(serverContent);

        if (localHash === serverHash) {
            return { status: 'safe', message: 'Only line endings differ' };
        } else {
            return { status: 'modified', message: 'Content is actually modified' };
        }
    } catch (error) {
        return { status: 'error', message: error.message };
    }
}

const args = process.argv.slice(2);
const outputDirIndex = args.indexOf('--output-dir');
let outputDir = null;
let clIds = args;

if (outputDirIndex !== -1) {
    outputDir = args[outputDirIndex + 1];
    clIds = args.filter((arg, i) => i !== outputDirIndex && i !== outputDirIndex + 1);
}

if (clIds.length === 0) {
    console.log("Usage: node check_line_endings.cjs <cl_id1> [cl_id2] ... [--output-dir <path>]");
    process.exit(1);
}

let summaryMarkdown = `# P4 Line Ending Check Summary\n\n`;
summaryMarkdown += `Generated on: ${new Date().toLocaleString()}\n\n---\n`;

clIds.forEach(clId => {
    console.log(`\n# Checking Changelist: ${clId}`);
    summaryMarkdown += `## Changelist: ${clId}\n\n`;

    try {
        const openedOutput = execSync(`p4 opened -c ${clId}`).toString();
        const lines = openedOutput.trim().split('\n').filter(l => l.trim());

        if (lines.length === 0 || (lines.length === 1 && lines[0].includes("not opened on this client"))) {
            console.log("_No files opened._");
            summaryMarkdown += `_No files opened in this changelist._\n\n`;
            return;
        }

        const safeFiles = [];
        const modifiedFiles = [];
        const skippedFiles = [];
        const errorFiles = [];

        lines.forEach(line => {
            const match = line.match(/^([^#]+)#\d+ - \w+ .* \((\w+)\)/);
            if (!match) return;

            const depotPath = match[1];
            const fileType = match[2];
            const result = checkFile(depotPath, fileType);

            if (result.status === 'safe') safeFiles.push(depotPath);
            else if (result.status === 'modified') modifiedFiles.push(depotPath);
            else if (result.status === 'skipped') skippedFiles.push(`${depotPath} (${fileType})`);
            else errorFiles.push(`${depotPath} (${result.message})`);
        });

        if (safeFiles.length > 0) {
            console.log(`✅ ${safeFiles.length} files safe to revert.`);
            summaryMarkdown += `### ✅ Safe to Revert (Only line endings differ)\n`;
            safeFiles.forEach(f => summaryMarkdown += `- \`${f}\` \n`);
            summaryMarkdown += `\n**Revert Command:**\n\`\`\`bash\np4 revert ${safeFiles.join(' ')}\n\`\`\`\n\n`;
        }

        if (modifiedFiles.length > 0) {
            console.log(`⚠️ ${modifiedFiles.length} files have real modifications.`);
            summaryMarkdown += `### ⚠️ Real Modifications\n`;
            modifiedFiles.forEach(f => summaryMarkdown += `- \`${f}\` \n`);
            summaryMarkdown += `\n`;
        }

        if (skippedFiles.length > 0) {
            summaryMarkdown += `### ℹ️ Skipped (Non-text)\n`;
            skippedFiles.forEach(f => summaryMarkdown += `- \`${f}\` \n`);
            summaryMarkdown += `\n`;
        }

    } catch (error) {
        summaryMarkdown += `> ❌ **Error processing CL:** ${error.message}\n\n`;
    }
    summaryMarkdown += `\n---\n\n`;
});

if (outputDir) {
    if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });
    const summaryPath = path.join(outputDir, `P4_LineEnding_Report_${Date.now()}.md`);
    fs.writeFileSync(summaryPath, summaryMarkdown);
    console.log(`\nSummary report exported to: ${summaryPath}`);
} else {
    console.log("\n(No output directory provided, summary file not created.)");
}
