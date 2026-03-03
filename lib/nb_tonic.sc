// nb_tonic v1.0 @sonoCircuit - based on supertonic @infinitedigits

NB_tonic {
	
	*initClass {
		
		var voxs, voxPrev, voxParams, tonicGroup, nozBuf;
		var numVoxs = 8;
		
		StartUp.add {
			
			var s = Server.default;
			
			voxs = Array.newClear(numVoxs);
			voxParams = Array.fill(numVoxs, {
				Dictionary.newFrom([
					\main_amp, 1,
					\level, 1,
					\pan, 0,
					\send_a, 0,
					\send_b, 0,
					\mix, 0.6,
					\dist, 0,
					\eq_freq, 632.4,
					\eq_gain, -12,
					\osc_attack, 0,
					\osc_decay, 0.500,
					\osc_wav, 0,
					\osc_freq, 120,
					\mod_mode, 0,
					\mod_rate, 400,
					\mod_amt, 18,
					\noise_attack, 0.026,
					\noise_decay, 0.800,
					\noise_freq, 2000,
					\noise_q, 2,
					\noise_mode, 0,
					\noise_env, 2,
					\noise_stereo, 1,
					\osc_vel, 1,
					\noise_vel, 0.2,
					\mod_vel, 1,
					\lpf_cut, 20000,
					\lpf_rez, 0
				]);
			});
			
			OSCFunc.new({ |msg|
				
				if (tonicGroup.isNil) {
					
					tonicGroup = Group.new(s);
					
					nozBuf = Buffer.loadCollection(s, FloatArray.fill(96000, { if(2.rand > 0) {1.0} {-1.0} }));
					
					SynthDef(\tonic,{
						arg outBus, sendABus, sendBBus, nBuf,
						gate = 1, vel = 0.5, main_amp = 1, level = 1, pan = 0, send_a = 0, send_b = 0,
						dist = 0, eq_freq = 632.4, eq_gain = -20, mix = 0.8,
						osc_wav = 1, osc_freq = 54, mod_mode = 1, mod_rate = 400, mod_amt = 18, osc_attack = 0, osc_decay = 0.500,
						noise_freq = 1000, noise_q = 2.5, noise_mode = 1, noise_env = 1,
						noise_stereo = 1, noise_attack = 0.026, noise_decay = 0.200,
						osc_vel = 1, noise_vel = 1, mod_vel = 1, lpf_cut = 20000, lpf_rez = 0;
						
						// variables
						var osc, noz, noz_post, snd, pitch_mod, num_claps, d_action, noz_a, noz_b,
						clap_freq, decayer, env_osc, env_exp, env_lin, env_dec, boost, att, lpf_rq;
						
						// lua-sc conversion (ugly, but I can't do this on the lua side due to the preview func)
						osc_wav = osc_wav - 1;
						mod_mode = mod_mode - 1;
						noise_mode = noise_mode - 1;
						noise_env = noise_env - 1;
						noise_stereo = noise_stereo - 1;
						
						// rescale and clamp
						vel = vel.linlin(0, 1, 0, 2);
						eq_freq = eq_freq.clip(20, 20000);
						lpf_cut = lpf_cut.clip(20, 20000);
						lpf_rq = lpf_rez.linlin(0, 1, 1, 0.05);
						clap_freq = (4311 / (noise_attack + 28.4)) + 11.44;
						decayer = SelectX.kr(dist, [0.05, dist * 0.3]);
						noise_decay = noise_decay * 1.4;
						
						// envelopes
						d_action = Select.kr(((osc_attack + osc_decay) > (noise_attack + noise_decay)), [0, 2]);
						env_osc = EnvGen.ar(Env.new([0.0001, 1, 0.9, 0.0001], [osc_attack, osc_decay * decayer, osc_decay], \exponential), gate, doneAction: d_action);
						env_exp = EnvGen.ar(Env.new([0.001, 1, 0.0001], [noise_attack, noise_decay], \exponential), gate, doneAction:(2 - d_action));
						env_lin = EnvGen.ar(Env.new([0.0001, 1, 0.9, 0.0001], [noise_attack, noise_decay * decayer,noise_decay * (1 - decayer)], \linear));
						env_dec = Decay.ar(Impulse.ar(clap_freq), clap_freq.reciprocal, 0.85, 0.15) * Trig.ar(1, noise_attack + 0.001) + EnvGen.ar(
							Env.new([0.001, 0.001, 1, 0.0001], [noise_attack,0.001, noise_decay], \exponential)
						);
						
						// pitch modulation
						pitch_mod = Select.ar(mod_mode, [
							Decay.ar(Impulse.ar(0.0001), (2 * mod_rate).reciprocal), // decay
							SinOsc.ar(mod_rate, pi), // sine
							LFNoise0.ar(4 * mod_rate).lag((4 * mod_rate).reciprocal) // random
						]);
						pitch_mod = pitch_mod * (mod_amt * 0.5) * vel.range(1 - mod_vel, 1);
						osc_freq = ((osc_freq + 5).cpsmidi + pitch_mod).midicps;
						
						// noise playback
						noz_a = PlayBuf.ar(1, nBuf, startPos: IRand.new(0, 96000), loop: 1);
						noz_b = PlayBuf.ar(1, nBuf, startPos: IRand.new(0, 96000), loop: 1);
						
						// oscillator
						osc = Select.ar(osc_wav, [
							SinOsc.ar(osc_freq),
							LFTri.ar(osc_freq) * 0.5,
							SawDPW.ar(osc_freq) * 0.5,
						]);
						osc = Select.ar(mod_mode > 1, [osc, SelectX.ar(osc_decay < 0.1, [LPF.ar(noz_b, mod_rate), osc])]) * env_osc;
						osc = (osc * vel.range(1 - osc_vel, 1)).softclip;
						
						// noise source
						noz = Select.ar(noise_stereo, [noz_a, [noz_a, noz_b]]);
						// noise filter
						noz_post = Select.ar(noise_mode,
							[
								BLowPass.ar(noz, noise_freq, Clip.kr(1/noise_q, 0.5, 3)),
								BBandPass.ar(noz, noise_freq, Clip.kr(2/noise_q, 0.1, 6)),
								BHiPass.ar(noz, noise_freq, Clip.kr(1/noise_q, 0.5, 3))
							]
						);
						noz_post = SelectX.ar((0.1092 * noise_q.log + 0.0343), [noz_post, SinOsc.ar(noise_freq)]);
						// noise env & vel
						noz = Splay.ar(noz_post * Select.ar(noise_env, [env_exp, env_lin, env_dec]));
						noz = (noz * vel.range(1 - noise_vel, 1)).softclip * -9.dbamp;
						
						// mix oscillator and noise
						snd = XFade2.ar(osc, noz, mix);
						// distortion
						snd = (snd * (1 - dist) + ((snd * dist.linlin(0, 1, 12, 24).dbamp).softclip * dist));
						snd = snd * dist.linlin(0, 1, 0, -6).dbamp;
						// eq after distortion
						snd = BPeakEQ.ar(snd, eq_freq, 1, eq_gain);
						// remove sub freq
						snd = HPF.ar(snd, 20);
						// final level
						snd = snd * level * main_amp * -6.dbamp;
						// lowpass
						snd = RLPF.ar(snd, lpf_cut, lpf_rq);
						// pan
						snd = Balance2.ar(snd[0], snd[1], pan);
						// output
						Out.ar(sendABus, send_a * snd);
						Out.ar(sendBBus, send_b * snd);
						Out.ar(outBus, snd);
					}).add;
					
				};
				
			}, "/nb_tonic/init");
			
			
			OSCFunc.new({ |msg|
				var idx = msg[1].asInteger;
				var vel = msg[2].asFloat;
				var chk = msg[3].asInteger;
				var syn;
				
				if (voxs[chk].notNil) { voxs[chk].release(0.05) }; // 50ms release time
				
				syn = Synth.new(\tonic,
					[
						\vel, vel,
						\nBuf, nozBuf,
						\sendABus, (~sendA ? s.outputBus),
						\sendBBus, (~sendB ? s.outputBus)
					] ++ voxParams[idx].getPairs
				);
				
				syn.onFree {
					if (voxs[chk].notNil && voxs[chk] === syn) { voxs[chk] = nil }
				};
				
				voxs[chk] = syn;
				
			}, "/nb_tonic/trig");
			
			OSCFunc.new({ |msg|
				var syn;
				
				if (voxPrev.notNil) { voxPrev.release(0.05) };
				
				syn = Synth.new(\tonic,
					[
						\main_amp, voxParams[0][\main_amp],
						\lpf_cut, 20000,
						\lpf_rez, 0,
						\vel, 1,
						\nBuf, nozBuf,
						\sendABus, (~sendA ? s.outputBus),
						\sendBBus, (~sendB ? s.outputBus)
					] ++ msg[1..]
				);
				
				syn.onFree {
					if (voxPrev.notNil && voxPrev === syn) { voxPrev = nil }
				};
				
				voxPrev = syn;
				
			}, "/nb_tonic/preview_start");
			
			OSCFunc.new({ |msg|
				if (voxPrev.notNil) {
					voxPrev.free;
					voxPrev = nil;
				}
			}, "/nb_tonic/preview_stop");
			
			OSCFunc.new({ |msg|
				var idx = msg[1].asInteger;
				var key = msg[2].asSymbol;
				var val = msg[3].asFloat;
				voxParams[idx][key] = val;
			}, "/nb_tonic/set_param");
			
			OSCFunc.new({ |msg|
				var val = msg[1].asFloat;
				numVoxs.do{ |idx|
					voxParams[idx][\main_amp] = val
				};
			}, "/nb_tonic/set_main_amp");
			
			OSCFunc.new({ |msg|
				var val = msg[1].asFloat;
				numVoxs.do{ |idx|
					voxParams[idx][\lpf_cut] = val
				};
			}, "/nb_tonic/set_cutoff");
			
			OSCFunc.new({ |msg|
				var val = msg[1].asFloat;
				numVoxs.do{ |idx|
					voxParams[idx][\lpf_rez] = val
				};
			}, "/nb_tonic/set_resonance");
			
		}
	}
}
