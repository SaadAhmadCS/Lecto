import { processRecording } from './processing-service.js';

interface ProcessingJob {
  recordingId: string;
  userId: string;
  addedAt: Date;
  status: 'queued' | 'processing' | 'completed' | 'failed';
  error?: string;
}

/**
 * Simple in-process job queue for recording processing.
 *
 * For V1, this runs sequentially in the same Node.js process.
 * In production, this would be replaced with BullMQ/Redis
 * or Cloud Tasks for distributed processing.
 */
class ProcessingQueue {
  private queue: ProcessingJob[] = [];
  private isProcessing = false;

  /**
   * Enqueue a recording for processing.
   * Processing starts automatically if the queue is idle.
   */
  enqueue(recordingId: string, userId: string): void {
    // Don't add duplicates
    const existing = this.queue.find(
      j => j.recordingId === recordingId && j.status === 'queued',
    );
    if (existing) {
      console.log(`ProcessingQueue: ${recordingId} already queued, skipping`);
      return;
    }

    this.queue.push({
      recordingId,
      userId,
      addedAt: new Date(),
      status: 'queued',
    });

    console.log(`ProcessingQueue: Enqueued ${recordingId} (${this.queueLength} in queue)`);

    // Auto-start processing
    if (!this.isProcessing) {
      this.processNext();
    }
  }

  /**
   * Process the next job in the queue.
   */
  private async processNext(): Promise<void> {
    const nextJob = this.queue.find(j => j.status === 'queued');
    if (!nextJob) {
      this.isProcessing = false;
      console.log('ProcessingQueue: Queue empty, idle');
      return;
    }

    this.isProcessing = true;
    nextJob.status = 'processing';

    try {
      await processRecording(nextJob.recordingId, nextJob.userId);
      nextJob.status = 'completed';
    } catch (error) {
      nextJob.status = 'failed';
      nextJob.error = error instanceof Error ? error.message : String(error);
      console.error(`ProcessingQueue: Job failed for ${nextJob.recordingId}:`, nextJob.error);
    }

    // Process next in queue
    await this.processNext();
  }

  /**
   * Get the current queue status.
   */
  getStatus() {
    return {
      isProcessing: this.isProcessing,
      queueLength: this.queueLength,
      jobs: this.queue.map(j => ({
        recordingId: j.recordingId,
        status: j.status,
        addedAt: j.addedAt,
        error: j.error,
      })),
    };
  }

  /**
   * Get the number of pending jobs.
   */
  get queueLength(): number {
    return this.queue.filter(j => j.status === 'queued').length;
  }

  /**
   * Check if a specific recording is being processed.
   */
  isRecordingQueued(recordingId: string): boolean {
    return this.queue.some(
      j => j.recordingId === recordingId && (j.status === 'queued' || j.status === 'processing'),
    );
  }
}

// Singleton instance
export const processingQueue = new ProcessingQueue();
