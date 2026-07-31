$baseUrl = 'http://localhost:3000/api/v1'

Write-Output 'Waiting for server...'
Start-Sleep -Seconds 5
$health = Invoke-RestMethod -Uri 'http://localhost:3000/health'
Write-Output "Health: $($health.status)"

$subjectResponse = Invoke-RestMethod -Uri "$baseUrl/subjects" -Method Post -ContentType 'application/json' -Body '{"name":"AI Test Subject"}'
$subjectId = $subjectResponse.data.id
Write-Output "Created Subject: $subjectId"

$recordingResponse = Invoke-RestMethod -Uri "$baseUrl/recordings" -Method Post -ContentType 'application/json' -Body "{`"subjectId`":`"$subjectId`", `"title`":`"Gemini Audio Test`"}"
$recordingId = $recordingResponse.data.id
Write-Output "Created Recording: $recordingId"

$chunkBody = "{`"sequenceNumber`":0, `"filePath`":`"C:\\Users\\hp\\Desktop\\Lecto\\backend-api\\test_audio.wav`", `"durationMs`":60000, `"sizeBytes`":1024000}"
$chunkResponse = Invoke-RestMethod -Uri "$baseUrl/recordings/$recordingId/chunks" -Method Post -ContentType 'application/json' -Body $chunkBody
Write-Output "Uploaded chunk metadata: $($chunkResponse.data.id)"

$processResponse = Invoke-RestMethod -Uri "$baseUrl/recordings/$recordingId/process" -Method Post -ContentType 'application/json' -Body '{}'
Write-Output 'Processing triggered.'

$isProcessing = $true
while ($isProcessing) {
    Start-Sleep -Seconds 3
    $statusResponse = Invoke-RestMethod -Uri "$baseUrl/recordings/$recordingId/status"
    $status = $statusResponse.data.processingStatus
    Write-Output "Current status: $status"
    if ($status -eq 'completed' -or $status -like '*failed*') {
        $isProcessing = $false
    }
}

if ($statusResponse.data.processingStatus -eq 'completed') {
    $summaryResponse = Invoke-RestMethod -Uri "$baseUrl/recordings/$recordingId/summary"
    Write-Output '================ FINAL SUMMARY ================'
    Write-Output $summaryResponse.data.content
    
    $transcriptResponse = Invoke-RestMethod -Uri "$baseUrl/recordings/$recordingId/transcript"
    Write-Output '================ FULL TRANSCRIPT ================'
    Write-Output $transcriptResponse.data.content
} else {
    Write-Output 'Processing failed.'
}
