import { ZxcvbnFactory } from '@zxcvbn-ts/core';
import { dictionary as common, adjacencyGraphs } from '@zxcvbn-ts/language-common';
import { dictionary as english, translations } from '@zxcvbn-ts/language-en';
export function estimate(password, personalWords) {
  // Never let the upstream substring limit produce a score for only a prefix.
  if (typeof password !== 'string' || password.length > 256) return {error: 'limit'};
  const engine = new ZxcvbnFactory({dictionary: {...common, ...english}, graphs: adjacencyGraphs, translations, maxLength: 256});
  const r = engine.check(password, personalWords);
  return {score:r.score, guesses:r.guesses, feedback:r.feedback,
    patterns:[...new Set(r.sequence.map(p => p.pattern))]};
}
