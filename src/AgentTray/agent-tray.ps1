<#
.SYNOPSIS
    Agentic Windows — System Tray Agent Launcher
    Provides Win+Space global hotkey + system tray icon.
    Runs persistently in the background.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class HotKeyManager {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_WIN = 0x0008;
    public const uint VK_SPACE = 0x20;
}
"@ -ReferencedAssemblies System.Windows.Forms

# ═══════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════
$DASHBOARD_URL  = "http://localhost:4774"
$TOOLTIP_TEXT   = "⚡ Agentic Windows`nWin+Space to invoke agent"

# ═══════════════════════════════════════════════
# Hidden window for hotkey message processing
# ═══════════════════════════════════════════════
$messageWindow = New-Object System.Windows.Forms.Form
$messageWindow.WindowState = "Minimized"
$messageWindow.ShowInTaskbar = $false
$messageWindow.Opacity = 0
$messageWindow.Add_Shown({ $messageWindow.Hide() })

# Register Win+Space
[HotKeyManager]::RegisterHotKey($messageWindow.Handle, 1, [HotKeyManager]::MOD_WIN, [HotKeyManager]::VK_SPACE) | Out-Null

# ═══════════════════════════════════════════════
# System tray icon
# ═══════════════════════════════════════════════
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Visible = $true
$icon.Text = $TOOLTIP_TEXT

# Create a simple icon programmatically (blue circle with "A")
$iconBitmap = New-Object System.Drawing.Bitmap(16, 16)
$g = [System.Drawing.Graphics]::FromImage($iconBitmap)
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse([System.Drawing.Brushes]::DodgerBlue, 0, 0, 16, 16)
$g.DrawString("A", (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, 2, 1)
$g.Dispose()
$iconHandle = $iconBitmap.GetHicon()
$icon.Icon = [System.Drawing.Icon]::FromHandle($iconHandle)

# ── Context menu ──
$menu = New-Object System.Windows.Forms.ContextMenuStrip

# Open Dashboard
$menuItemDashboard = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemDashboard.Text = "📊 Open Dashboard"
$menuItemDashboard.Add_Click({
    try { Start-Process $DASHBOARD_URL } catch {}
})
$menu.Items.Add($menuItemDashboard) | Out-Null

# Open Terminal with Hermes
$menuItemTerminal = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemTerminal.Text = "🖥️ Open Agent Terminal"
$menuItemTerminal.Add_Click({
    try { Start-Process "powershell" -ArgumentList "-NoExit hermes" } catch {}
})
$menu.Items.Add($menuItemTerminal) | Out-Null

# Separator
$menu.Items.Add("-") | Out-Null

# System Health
$menuItemHealth = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemHealth.Text = "🩺 Run Health Check"
$menuItemHealth.Add_Click({
    try { Start-Process "powershell" -ArgumentList "-NoExit -Command hermes run skill system-health" -WindowStyle Hidden } catch {}
})
$menu.Items.Add($menuItemHealth) | Out-Null

# Clean Disk
$menuItemDisk = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemDisk.Text = "🧹 Clean Disk"
$menuItemDisk.Add_Click({
    try { Start-Process "powershell" -ArgumentList "-NoExit -Command hermes run skill disk-guardian" -WindowStyle Hidden } catch {}
})
$menu.Items.Add($menuItemDisk) | Out-Null

# Separator
$menu.Items.Add("-") | Out-Null

# Restart Hermes
$menuItemRestart = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemRestart.Text = "🔄 Restart Agent"
$menuItemRestart.Add_Click({
    try {
        Get-Process -Name "hermes" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Process "powershell" -ArgumentList "-WindowStyle Hidden -Command hermes run"
    } catch {}
})
$menu.Items.Add($menuItemRestart) | Out-Null

# Separator
$menu.Items.Add("-") | Out-Null

# Exit
$menuItemExit = New-Object System.Windows.Forms.ToolStripMenuItem
$menuItemExit.Text = "❌ Exit"
$menuItemExit.Add_Click({
    $icon.Visible = $false
    [HotKeyManager]::UnregisterHotKey($messageWindow.Handle, 1)
    [System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($menuItemExit) | Out-Null

$icon.ContextMenuStrip = $menu

# ── Click action (single left-click = open dashboard) ──
$icon.Add_Click({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        try { Start-Process $DASHBOARD_URL } catch {}
    }
})

# Optional: show balloon on first start
$icon.ShowBalloonTip(3000, "Agentic Windows", "Agent running. Press Win+Space to invoke.", [System.Windows.Forms.ToolTipIcon]::Info)

# ═══════════════════════════════════════════════
# Hotkey handler: Win+Space → open quick dialog
# ═══════════════════════════════════════════════
$messageWindow.Add_WndProc({
    param($sender, $m)
    if ($m.Msg -eq [HotKeyManager]::WM_HOTKEY) {
        Show-AgentInput
    }
})

# ═══════════════════════════════════════════════
# Function: Show agent command input dialog
# ═══════════════════════════════════════════════
function Show-AgentInput {
    # Create a small input dialog
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "⚡ Agentic Windows — Ask the agent"
    $form.Width = 550
    $form.Height = 180
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.ControlBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "What do you want to do?"
    $label.Location = New-Object System.Drawing.Point(15, 15)
    $label.Size = New-Object System.Drawing.Size(500, 20)
    $label.ForeColor = [System.Drawing.Color]::DodgerBlue
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(15, 40)
    $textBox.Size = New-Object System.Drawing.Size(500, 25)
    $textBox.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $textBox.ForeColor = [System.Drawing.Color]::White
    $textBox.BorderStyle = "FixedSingle"
    $textBox.Focus()
    $form.Controls.Add($textBox)

    $submitBtn = New-Object System.Windows.Forms.Button
    $submitBtn.Text = "▶  Send to Agent"
    $submitBtn.Location = New-Object System.Drawing.Point(15, 75)
    $submitBtn.Size = New-Object System.Drawing.Size(130, 30)
    $submitBtn.BackColor = [System.Drawing.Color]::DodgerBlue
    $submitBtn.ForeColor = [System.Drawing.Color]::White
    $submitBtn.FlatStyle = "Flat"
    $submitBtn.DialogResult = "OK"
    $form.Controls.Add($submitBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel (Esc)"
    $cancelBtn.Location = New-Object System.Drawing.Point(155, 75)
    $cancelBtn.Size = New-Object System.Drawing.Size(100, 30)
    $cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $cancelBtn.ForeColor = [System.Drawing.Color]::White
    $cancelBtn.FlatStyle = "Flat"
    $cancelBtn.DialogResult = "Cancel"
    $form.Controls.Add($cancelBtn)

    # Enter in textbox = submit
    $textBox.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            $form.Close()
            $form.DialogResult = "OK"
        }
        if ($_.KeyCode -eq "Escape") {
            $form.Close()
            $form.DialogResult = "Cancel"
        }
    })

    $result = $form.ShowDialog()

    if ($result -eq "OK" -and $textBox.Text.Trim().Length -gt 0) {
        $command = $textBox.Text.Trim()
        # Send the command to Hermes via a terminal
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-WindowStyle Normal -NoExit -Command hermes `"$($command.Replace('"', '""'))`""
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Could not send command to agent: $($_.Exception.Message)", "Agentic Windows", "OK", "Warning")
        }
    }

    $form.Dispose()
}

# ═══════════════════════════════════════════════
# Main loop
# ═══════════════════════════════════════════════
[System.Windows.Forms.Application]::Run($messageWindow)
