<#
.SYNOPSIS
  Pastes the CURRENT CLIPBOARD into a new Microsoft Word document (COM) and reports which runs are bold,
  which paragraphs use Heading styles and which are list items. Nothing is saved; Word is closed without saving.
  Needs desktop Word. Run it right after copying formatted text in Pellucid (select bold/heading/bullet text, Ctrl+C):

  powershell -ExecutionPolicy Bypass -File D:\projects\pellucid\writer_app\tool\windows\word_paste_check.ps1

  -Visible shows Word while it works. Word may create AutoRecover/temp files under its own folders on C:
  (Word does that on its own for any unsaved doc); the script saves nothing.
  Exit 0 = rich content found (at least one bold run or heading or list), 1 = plain only, 2 = Word unavailable.
#>
[CmdletBinding()]
param([switch]$Visible)
$ErrorActionPreference = 'Stop'
try { $word = New-Object -ComObject Word.Application } catch { Write-Host 'Microsoft Word is not installed / cannot be started.'; exit 2 }
$word.Visible = [bool]$Visible
$word.DisplayAlerts = 0
$doc = $null
try {
  $doc = $word.Documents.Add()
  $word.Selection.Paste()
  Start-Sleep -Milliseconds 500
  $paras = $doc.Paragraphs
  "Paragraphs: $($paras.Count)"
  $rich = 0
  $i = 0
  foreach ($p in $paras) {
    $i++
    $text = $p.Range.Text.TrimEnd("`r", "`a", "`n")
    $style = $p.Style.NameLocal
    $isHeading = $p.OutlineLevel -ge 1 -and $p.OutlineLevel -le 9 -or $style -like 'Heading*'
    $isList = $p.Range.ListFormat.ListType -ne 0
    # bold runs: walk words, group consecutive bold ones
    $runs = @(); $cur = ''
    foreach ($w in $p.Range.Words) {
      if ($w.Bold -eq -1) { $cur += $w.Text } else { if ($cur) { $runs += $cur.Trim(); $cur = '' } }
    }
    if ($cur) { $runs += $cur.Trim() }
    $tags = @()
    if ($isHeading) { $tags += "HEADING($style, outline $($p.OutlineLevel))"; $rich++ }
    if ($isList) { $tags += "LIST($($p.Range.ListFormat.ListString))"; $rich++ }
    if ($runs) { $tags += "BOLD runs: " + (($runs | ForEach-Object { '"' + $_ + '"' }) -join ', '); $rich++ }
    "{0,2}. [{1}] {2}  {3}" -f $i, $style, $text, ($tags -join ' ')
  }
  $all = $doc.Content.Text
  if ($all -match '\*\*' -or $all -match '(^|\r)#+ ') { Write-Host 'WARNING: literal markdown markers (** or #) found in the pasted text.' -ForegroundColor Yellow; $rich = 0 }
  if ($rich -gt 0) { Write-Host 'RESULT: rich formatting arrived in Word' -ForegroundColor Green; $rc = 0 }
  else { Write-Host 'RESULT: plain text only (no bold, headings or lists)' -ForegroundColor Red; $rc = 1 }
} finally {
  if ($doc) { $doc.Close(0) }   # wdDoNotSaveChanges
  $word.Quit(0)
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
exit $rc
