/**
 * Unified AI Service — Supports both Gemini and OpenAI with automatic fallback.
 *
 * Provider modes (AI_PROVIDER env var):
 * - 'gemini': Use Gemini only
 * - 'openai': Use OpenAI only
 * - 'auto': Try OpenAI first (paid, reliable), fall back to Gemini
 *
 * Each provider has the same system instructions to ensure consistent output
 * regardless of which model actually processes the request.
 */

import { GoogleGenAI } from '@google/genai';
import OpenAI from 'openai';
import { readFile } from 'fs/promises';
import { createReadStream } from 'fs';
import { env } from '../config/env.js';

// ─── Provider Clients ──────────────────────────────────────────────

const gemini = env.GEMINI_API_KEY
  ? new GoogleGenAI({ apiKey: env.GEMINI_API_KEY })
  : null;

const openai = env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: env.OPENAI_API_KEY })
  : null;

// ─── Retry Logic ───────────────────────────────────────────────────

const MAX_RETRIES = 3;

async function withRetry<T>(fn: () => Promise<T>, label: string): Promise<T> {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (error: unknown) {
      const errMsg = error instanceof Error ? error.message : String(error);
      const isRateLimit = errMsg.includes('429') || errMsg.includes('RESOURCE_EXHAUSTED') || errMsg.includes('rate_limit');
      const isServerError = errMsg.includes('503') || errMsg.includes('UNAVAILABLE') || errMsg.includes('500');
      const isRetryable = isRateLimit || isServerError;

      if (!isRetryable || attempt === MAX_RETRIES) {
        throw error;
      }

      const retryMatch = errMsg.match(/retry in (\d+(?:\.\d+)?)s/i);
      const delayMs = retryMatch
        ? Math.ceil(parseFloat(retryMatch[1]) * 1000)
        : Math.min(1000 * Math.pow(2, attempt), 60000);

      console.log(`  ⏳ ${label}: Retrying in ${Math.round(delayMs / 1000)}s (attempt ${attempt}/${MAX_RETRIES})...`);
      await delay(delayMs);
    }
  }
  throw new Error(`${label}: Max retries exceeded`);
}

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ─── System Instructions ───────────────────────────────────────────

const TRANSCRIPTION_SYSTEM_INSTRUCTION = `You are Lecto, an AI lecture transcription assistant. Your task is to create a clean, structured markdown transcript from the provided audio.

RULES:
1. Output clean, structured markdown text.
2. Use "## " headings when the instructor shifts to a new major topic.
3. Use "### " subheadings for sub-topics within a section.
4. Preserve technical terms, proper nouns, and discipline-specific terminology exactly as spoken.
5. Mark genuinely unclear audio as [inaudible]. Do NOT guess at words you cannot hear.
6. Keep speaker attribution minimal. Only use "**Instructor:**" or "**Student:**" when there's a clear dialogue exchange.
7. Format mathematical equations using LaTeX: $equation$ for inline, $$equation$$ for display.
8. Use bullet points for listed items the instructor enumerates.
9. Do NOT add your own commentary, opinions, or editorial notes.
10. Do NOT add introductory text like "Here is the transcript..." — start directly with the content.
11. The lecture may be in English, Urdu, or a mix of both. Transcribe in the language spoken. For Urdu, use Roman Urdu (English alphabet).
12. If the instructor references something written on the board, note it as [Board: description if audible].`;

const SUMMARY_SYSTEM_INSTRUCTION = `You are Lecto, an AI study notes generator. You will receive a complete lecture transcript in markdown format. Generate comprehensive, well-structured study notes.

OUTPUT FORMAT (use this exact structure):

# Lecture Summary

## Overview
A 2-3 sentence high-level summary of what was covered in this lecture.

## Key Concepts
- **Concept Name**: Clear explanation (2-3 sentences)
- (repeat for all important concepts)

## Topic Breakdown

### [Topic 1 Name]
Detailed explanation of the topic as covered in the lecture. Include relevant formulas, examples, and important details.

### [Topic 2 Name]
(repeat for each distinct topic)

## Important Formulas & Equations
- $formula$ — what it represents
- (list all formulas mentioned)

## Definitions
- **Term**: Definition as given in the lecture
- (list key definitions)

## Examples Discussed
1. **Example description**: Solution/approach discussed
2. (list examples)

## Assignments & Action Items
- [ ] Any homework, reading, or tasks mentioned by the instructor
- (leave empty section if none mentioned)

## Key Takeaways
1. Most important point from the lecture
2. Second most important
3. (3-5 takeaways)

RULES:
1. Be thorough — a student who missed the lecture should be able to study from these notes alone.
2. Preserve all technical accuracy. Do not simplify formulas or theorems.
3. Use LaTeX for all math: $inline$ and $$display$$.
4. If photos/board captures are referenced, note what they contained.
5. Do NOT add information not present in the transcript.
6. Keep language clear and student-friendly.`;

// ─── Gemini Provider ───────────────────────────────────────────────

async function geminiTranscribe(audioFilePath: string, chunkIndex: number, totalChunks: number): Promise<string> {
  if (!gemini) throw new Error('Gemini API key not configured');

  const audioData = await readFile(audioFilePath);
  const base64Audio = audioData.toString('base64');

  const ext = audioFilePath.split('.').pop()?.toLowerCase();
  const mimeType = ext === 'mp3' ? 'audio/mp3'
    : ext === 'wav' ? 'audio/wav'
    : ext === 'ogg' ? 'audio/ogg'
    : 'audio/mp4';

  const contextNote = totalChunks > 1
    ? `\n\nCONTEXT: This is chunk ${chunkIndex + 1} of ${totalChunks} from a lecture recording. Maintain continuity with natural paragraph flow.`
    : '';

  const response = await gemini.models.generateContent({
    model: env.GEMINI_MODEL,
    contents: [{
      role: 'user',
      parts: [
        { inlineData: { mimeType, data: base64Audio } },
        { text: `Transcribe this audio lecture recording into structured markdown.${contextNote}` },
      ],
    }],
    config: {
      systemInstruction: TRANSCRIPTION_SYSTEM_INSTRUCTION,
      temperature: 0.1,
      maxOutputTokens: 8192,
    },
  });

  if (!response.text) throw new Error('Gemini returned empty transcription');
  return response.text.trim();
}

async function geminiSummarize(fullTranscript: string, title: string, photoDescriptions: string[]): Promise<string> {
  if (!gemini) throw new Error('Gemini API key not configured');

  let prompt = `Generate comprehensive study notes from this lecture transcript.\n\n`;
  prompt += `**Lecture Title:** ${title}\n\n`;
  if (photoDescriptions.length > 0) {
    prompt += `**Board/Screen Photos Captured:**\n`;
    photoDescriptions.forEach((desc, i) => { prompt += `- Photo ${i + 1}: ${desc}\n`; });
    prompt += `\n`;
  }
  prompt += `**Full Transcript:**\n\n${fullTranscript}`;

  const response = await gemini.models.generateContent({
    model: env.GEMINI_MODEL,
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    config: {
      systemInstruction: SUMMARY_SYSTEM_INSTRUCTION,
      temperature: 0.3,
      maxOutputTokens: 8192,
    },
  });

  if (!response.text) throw new Error('Gemini returned empty summary');
  return response.text.trim();
}

// ─── OpenAI Provider ───────────────────────────────────────────────

async function openaiTranscribe(audioFilePath: string, chunkIndex: number, totalChunks: number): Promise<string> {
  if (!openai) throw new Error('OpenAI API key not configured');

  // Step 1: Whisper for raw transcription
  const file = createReadStream(audioFilePath);
  const whisperResponse = await openai.audio.transcriptions.create({
    model: env.OPENAI_TRANSCRIPTION_MODEL,
    file,
    response_format: 'text',
    language: 'en', // Whisper auto-detects but hint helps
  });

  const rawText = typeof whisperResponse === 'string' ? whisperResponse : String(whisperResponse);

  if (!rawText || rawText.trim().length === 0) {
    throw new Error('Whisper returned empty transcription');
  }

  // Step 2: GPT to structure the raw transcript into markdown
  const contextNote = totalChunks > 1
    ? `\nThis is chunk ${chunkIndex + 1} of ${totalChunks} from a lecture recording.`
    : '';

  const structuredResponse = await openai.chat.completions.create({
    model: env.OPENAI_CHAT_MODEL,
    messages: [
      { role: 'system', content: TRANSCRIPTION_SYSTEM_INSTRUCTION },
      {
        role: 'user',
        content: `Structure this raw lecture transcription into clean, organized markdown. Preserve all content exactly — do not summarize or remove anything. Just add structure (headings, formatting, speaker labels where clear).${contextNote}\n\nRAW TRANSCRIPTION:\n${rawText}`,
      },
    ],
    temperature: 0.1,
    max_tokens: 8192,
  });

  const text = structuredResponse.choices[0]?.message?.content;
  if (!text) throw new Error('GPT returned empty structured transcript');
  return text.trim();
}

async function openaiSummarize(fullTranscript: string, title: string, photoDescriptions: string[]): Promise<string> {
  if (!openai) throw new Error('OpenAI API key not configured');

  let prompt = `Generate comprehensive study notes from this lecture transcript.\n\n`;
  prompt += `**Lecture Title:** ${title}\n\n`;
  if (photoDescriptions.length > 0) {
    prompt += `**Board/Screen Photos Captured:**\n`;
    photoDescriptions.forEach((desc, i) => { prompt += `- Photo ${i + 1}: ${desc}\n`; });
    prompt += `\n`;
  }
  prompt += `**Full Transcript:**\n\n${fullTranscript}`;

  const response = await openai.chat.completions.create({
    model: env.OPENAI_CHAT_MODEL,
    messages: [
      { role: 'system', content: SUMMARY_SYSTEM_INSTRUCTION },
      { role: 'user', content: prompt },
    ],
    temperature: 0.3,
    max_tokens: 8192,
  });

  const text = response.choices[0]?.message?.content;
  if (!text) throw new Error('GPT returned empty summary');
  return text.trim();
}

// ─── Unified API with Fallback ─────────────────────────────────────

type Provider = 'gemini' | 'openai';

function getProviderOrder(): Provider[] {
  switch (env.AI_PROVIDER) {
    case 'gemini': return ['gemini'];
    case 'openai': return ['openai'];
    case 'auto':
    default:
      // Auto: try OpenAI first (paid/reliable), fall back to Gemini
      const order: Provider[] = [];
      if (openai) order.push('openai');
      if (gemini) order.push('gemini');
      return order;
  }
}

async function withFallback<T>(
  label: string,
  geminiCall: () => Promise<T>,
  openaiCall: () => Promise<T>,
): Promise<T> {
  const providers = getProviderOrder();

  if (providers.length === 0) {
    throw new Error('No AI provider configured. Set GEMINI_API_KEY or OPENAI_API_KEY.');
  }

  let lastError: Error | undefined;

  for (let i = 0; i < providers.length; i++) {
    const provider = providers[i];
    const isLastProvider = i === providers.length - 1;

    try {
      const fn = provider === 'gemini' ? geminiCall : openaiCall;

      // Only retry on the last provider — fail fast on primary to enable quick fallback
      const result = isLastProvider
        ? await withRetry(fn, `${label} [${provider}]`)
        : await fn();

      console.log(`  🤖 ${label}: Success via ${provider}`);
      return result;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      console.warn(`  ⚠️  ${label}: ${provider} failed — ${lastError.message.slice(0, 120)}`);

      if (!isLastProvider) {
        console.log(`  🔄 ${label}: Falling back to next provider...`);
      }
    }
  }

  throw lastError ?? new Error(`${label}: All providers failed`);
}

// ─── Public API ────────────────────────────────────────────────────

/**
 * Transcribe a single audio chunk using the configured AI provider(s).
 */
export async function transcribeAudioChunk(
  audioFilePath: string,
  chunkIndex: number,
  totalChunks: number,
): Promise<string> {
  return withFallback(
    `Transcribe chunk ${chunkIndex + 1}`,
    () => geminiTranscribe(audioFilePath, chunkIndex, totalChunks),
    () => openaiTranscribe(audioFilePath, chunkIndex, totalChunks),
  );
}

/**
 * Generate structured study notes from a full transcript.
 */
export async function generateSummary(
  fullTranscript: string,
  title: string,
  photoDescriptions: string[] = [],
): Promise<string> {
  return withFallback(
    'Generate summary',
    () => geminiSummarize(fullTranscript, title, photoDescriptions),
    () => openaiSummarize(fullTranscript, title, photoDescriptions),
  );
}
