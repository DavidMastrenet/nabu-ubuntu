/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Based on the code from http://jgt.akpeters.com/papers/McGuire08/
 *
 * Efficient, High-Quality Bayer Demosaic Filtering on GPUs
 *
 * Morgan McGuire
 *
 * This paper appears in issue Volume 13, Number 4.
 * ---------------------------------------------------------
 * Copyright (c) 2008, Morgan McGuire. All rights reserved.
 *
 *
 * Modified by Linaro Ltd for 10/12-bit packed vs 8-bit raw Bayer format,
 * and for simpler demosaic algorithm.
 * Copyright (C) 2020, Linaro
 *
 * bayer_1x_packed.frag - Fragment shader code for raw Bayer 10-bit and 12-bit
 * packed formats
 */

#ifdef GL_ES
precision highp float;
#endif

/*
 * These constants are used to select the bytes containing the HS part of
 * the pixel value:
 * BPP - bytes per pixel,
 * THRESHOLD_L = fract(BPP) * 0.5 + 0.02
 * THRESHOLD_H = 1.0 - fract(BPP) * 1.5 + 0.02
 * Let X is the x coordinate in the texture measured in bytes (so that the
 * range is from 0 to (stride_-1)) aligned on the nearest pixel.
 * E.g. for RAW10P:
 * -------------+-------------------+-------------------+--
 *  pixel No    |  0   1    2   3   |  4   5    6   7   | ...
 * -------------+-------------------+-------------------+--
 *  byte offset | 0   1   2   3   4 | 5   6   7   8   9 | ...
 * -------------+-------------------+-------------------+--
 *      X       | 0.0 1.25 2.5 3.75 | 5.0 6.25 7.5 8.75 | ...
 * -------------+-------------------+-------------------+--
 * If fract(X) < THRESHOLD_L then the previous byte contains the LS
 * bits of the pixel values and needs to be skipped.
 * If fract(X) > THRESHOLD_H then the next byte contains the LS bits
 * of the pixel values and needs to be skipped.
 */
#if defined(RAW10P)
#define BPP		1.25
#define THRESHOLD_L	0.14
#define THRESHOLD_H	0.64
#elif defined(RAW12P)
#define BPP		1.5
#define THRESHOLD_L	0.27
#define THRESHOLD_H	0.27
#else
#error Invalid raw format
#endif


varying vec2 textureOut;

/* the texture size in pixels */
uniform vec2 tex_size;
uniform vec2 tex_step;
uniform vec2 tex_bayer_first_red;

uniform sampler2D tex_y;
uniform mat3 ccm;
uniform vec3 blacklevel;
uniform float gamma;
uniform float contrastExp;

float apply_contrast(float value)
{
	// Apply simple S-curve
	if (value < 0.5)
		return 0.5 * pow(value / 0.5, contrastExp);
	else
		return 1.0 - 0.5 * pow((1.0 - value) / 0.5, contrastExp);
}


/* Address packed bytes at texel centres; reflect neighbours at image edges. */
float rawPixel(vec2 p)
{
	p = abs(p);
	p = min(p, 2.0 * (tex_size - 1.0) - p);
	p = clamp(p, vec2(0.0), tex_size - 1.0);
#if defined(RAW10P)
	float position = mod(p.x, 4.0);
	float base = floor(p.x / 4.0) * 5.0;
	float highByte = floor(texture2D(tex_y,
		(vec2(base + position, p.y) + 0.5) * tex_step).r * 255.0 + 0.5);
	float lowByte = floor(texture2D(tex_y,
		(vec2(base + 4.0, p.y) + 0.5) * tex_step).r * 255.0 + 0.5);
	return (highByte * 4.0 + mod(floor(lowByte / pow(4.0, position)), 4.0)) / 1023.0;
#else
	float position = mod(p.x, 2.0);
	float base = floor(p.x / 2.0) * 3.0;
	float highByte = floor(texture2D(tex_y,
		(vec2(base + position, p.y) + 0.5) * tex_step).r * 255.0 + 0.5);
	float lowByte = floor(texture2D(tex_y,
		(vec2(base + 2.0, p.y) + 0.5) * tex_step).r * 255.0 + 0.5);
	return (highByte * 16.0 + mod(floor(lowByte / pow(16.0, position)), 16.0)) / 4095.0;
#endif
}

void main(void)
{
	vec2 p = clamp(floor(textureOut * tex_size), vec2(0.0), tex_size - 1.0);
	float center = rawPixel(p);
	float vertical = (rawPixel(p + vec2(0.0, -1.0)) + rawPixel(p + vec2(0.0, 1.0))) * 0.5;
	float horizontal = (rawPixel(p + vec2(-1.0, 0.0)) + rawPixel(p + vec2(1.0, 0.0))) * 0.5;
	float diagonal = (rawPixel(p + vec2(-1.0, -1.0)) + rawPixel(p + vec2(1.0, -1.0)) +
		rawPixel(p + vec2(-1.0, 1.0)) + rawPixel(p + vec2(1.0, 1.0))) * 0.25;
	vec2 alternate = mod(p + tex_bayer_first_red, 2.0);
	bool even_col = alternate.x < 1.0;
	bool even_row = alternate.y < 1.0;
	vec3 rgb = even_col ?
		(even_row ? vec3(center, (vertical + horizontal) * 0.5, diagonal) :
		 vec3(vertical, center, horizontal)) :
		(even_row ? vec3(horizontal, center, vertical) :
		 vec3(diagonal, (vertical + horizontal) * 0.5, center));

	rgb = rgb - blacklevel;

	/*
	 *   CCM is a 3x3 in the format
	 *
	 *   +--------------+----------------+---------------+
	 *   | RedRedGain   | RedGreenGain   | RedBlueGain   |
	 *   +--------------+----------------+---------------+
	 *   | GreenRedGain | GreenGreenGain | GreenBlueGain |
	 *   +--------------+----------------+---------------+
	 *   | BlueRedGain  |  BlueGreenGain | BlueBlueGain  |
	 *   +--------------+----------------+---------------+
	 *
	 *   Rout = RedRedGain * Rin + RedGreenGain * Gin + RedBlueGain * Bin
	 *   Gout = GreenRedGain * Rin + GreenGreenGain * Gin + GreenBlueGain * Bin
	 *   Bout = BlueRedGain * Rin + BlueGreenGain * Gin + BlueBlueGain * Bin
	 *
	 *   We upload to the GPU without transposition glUniformMatrix3f(.., .., GL_FALSE, ccm);
	 *
	 *   CPU
	 *   float ccm [] = {
	 *             RedRedGain,   RedGreenGain,   RedBlueGain,
	 *             GreenRedGain, GreenGreenGain, GreenBlueGain,
	 *             BlueRedGain,  BlueGreenGain,  BlueBlueGain,
	 *   };
	 *
	 *   GPU
	 *   ccm = {
	 *             RedRedGain,   GreenRedGain,   BlueRedGain,
	 *             RedGreenGain, GreenGreenGain, BlueGreenGain,
	 *             RedBlueGain,  GreenBlueGain,  BlueBlueGain,
	 *   }
	 *
	 *   However the indexing for the mat data-type is column major hence
	 *   ccm[0][0] = RedRedGain, ccm[0][1] = RedGreenGain, ccm[0][2] = RedBlueGain
	 *
	 */
	float rin, gin, bin;
	rin = rgb.r;
	gin = rgb.g;
	bin = rgb.b;

	rgb.r = (rin * ccm[0][0]) + (gin * ccm[0][1]) + (bin * ccm[0][2]);
	rgb.g = (rin * ccm[1][0]) + (gin * ccm[1][1]) + (bin * ccm[1][2]);
	rgb.b = (rin * ccm[2][0]) + (gin * ccm[2][1]) + (bin * ccm[2][2]);

	/*
	 * Contrast
	 * contrastExp 0..2 contrast to 0..infinity; avoid actual infinity at tan(pi/2)
	 */
	rgb = clamp(rgb, 0.0, 1.0);
	rgb.r = apply_contrast(rgb.r);
	rgb.g = apply_contrast(rgb.g);
	rgb.b = apply_contrast(rgb.b);

	/* Apply gamma after colour correction */
	rgb = pow(rgb, vec3(gamma));

#if defined (SWAP_BLUE)
	gl_FragColor = vec4(rgb.bgr, 1.0);
#else
	gl_FragColor = vec4(rgb, 1.0);
#endif
}
