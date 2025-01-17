﻿// Written in the D programming language

/**
 * A D programming language implementation of the
 * General Decimal Arithmetic Specification,
 * Version 1.70, (25 March 2009).
 * (http://www.speleotrove.com/decimal/decarith.pdf)
 *
 * License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors: Paul D. Anderson
 */
/*	Copyright Paul D. Anderson 2009 - 2011.
 *	Distributed under the Boost Software License, Version 1.0.
 *	(See accompanying file LICENSE_1_0.txt or copy at
 *	http://www.boost.org/LICENSE_1_0.txt)
 */

module decimal.dec32;

import std.array: insertInPlace;
import std.bigint;
import std.bitmanip;
import std.conv;
import std.string;

import decimal.arithmetic;
import decimal.context;
import decimal.decimal;
import decimal.logical;
import decimal.rounding;

unittest {
	writeln("-------------------");
	writeln("dec32.........begin");
	writeln("-------------------");
}

struct Dec32 {

private:
	// The total number of bits in the decimal number.
	// This is equal to the number of bits in the underlying integer;
	// (must be 32, 64, or 128).
	immutable uint bitLength = 32;

	// the number of bits in the sign bit (1, obviously)
	immutable uint signBit = 1;

	// The number of bits in the unsigned value of the decimal number.
	immutable uint unsignedBits = 31; // = bitLength - signBit;

	// The number of bits in the (biased) exponent.
	immutable uint expoBits = 8;

	// The number of bits in the coefficient when the value is
	// explicitly represented.
	immutable uint explicitBits = 23;

	// The number of bits used to indicate special values and implicit
	// representation
	immutable uint testBits = 2;

	// The number of bits in the coefficient when the value is implicitly
	// represented. The three missing bits (the most significant bits)
	// are always '100'.
	immutable uint implicitBits = 21; // = explicitBits - testBits;

	// The number of special bits, including the two test bits.
	// These bits are used to denote infinities and NaNs.
	immutable uint specialBits = 4;

	// The number of bits that follow the special bits.
	// Their number is the number of bits in an special value
	// when the others (sign and special) are accounted for.
	immutable uint spclPadBits = 27;
			// = bitLength - infinityBits - signBit;

	// The number of infinity bits, including the special bits.
	// These bits are used to denote infinity.
	immutable uint infinityBits = 5;

	// The number of bits that follow the special bits in infinities.
	// These bits are always set to zero in canonical representations.
	// Their number is the remaining number of bits in an infinity
	// when all others (sign and infinity) are accounted for.
	immutable uint infPadBits = 26;
			// = bitLength - infinityBits - signBit;

	// The number of nan bits, including the special bits.
	// These bits are used to denote NaN.
	immutable uint nanBits = 6;

	// The number of bits in the payload of a NaN.
	immutable uint payloadBits = 16;

	// The number of bits that follow the nan bits in NaNs.
	// These bits are always set to zero in canonical representations.
	// Their number is the remaining number of bits in a NaN
	// when all others (sign, nan and payload) are accounted for.
	immutable uint nanPadBits = 9;
			// = bitLength - payloadBits - specialBits - signBit;

	// length of the coefficient in decimal digits.
	immutable int PRECISION = 7;
	// The maximum coefficient that fits in an explicit number.
	immutable uint C_MAX_EXPLICIT = 0x7FFFFF; // = 8388607;
	// The maximum coefficient allowed in an implicit number.
	immutable uint C_MAX_IMPLICIT = 9999999;  // = 0x98967F;
	// masks for coefficients
	immutable uint C_IMPLICIT_MASK = 0x1FFFFF;
	immutable uint C_EXPLICIT_MASK = 0x7FFFFF;

	// The maximum unbiased exponent. The largest binary number that can fit
	// in the width of the exponent field without setting
	// either of the first two bits to 1.
	immutable uint MAX_EXPO = 0xBF; // = 191
	// The exponent bias. The exponent is stored as an unsigned number and
	// the bias is subtracted from the unsigned value to give the true
	// (signed) exponent.
	immutable int BIAS = 101;		// = 0x65
	// The maximum representable exponent.
	immutable int E_LIMIT = 191; 	// MAX_EXPO - BIAS
	// The min and max adjusted exponents.
	immutable int E_MAX =  96;		// E_LIMIT + PRECISION - 1
	immutable int E_MIN = -95;		// = 1 - E_MAX

	/// The context for this type.
	public static DecimalContext
        context32 = DecimalContext(PRECISION, E_MAX, Rounding.HALF_EVEN);

	// union providing different views of the number representation.
	union {

		// entire 32-bit unsigned integer
		uint intBits = SV.POS_NAN;	  // set to the initial value: NaN

		// unsigned value and sign bit
		mixin (bitfields!(
			uint, "uBits", unsignedBits,
			bool, "signed", signBit)
		);
		// Ex = explicit finite number:
		//	   full coefficient, exponent and sign
		mixin (bitfields!(
			uint, "mantEx", explicitBits,
			uint, "expoEx", expoBits,
			bool, "signEx", signBit)
		);
		// Im = implicit finite number:
		//		partial coefficient, exponent, test bits and sign bit.
		mixin (bitfields!(
			uint, "mantIm", implicitBits,
			uint, "expoIm", expoBits,
			uint, "testIm", testBits,
			bool, "signIm", signBit)
		);
		// Spcl = special values: non-finite numbers
		//		unused bits, special bits and sign bit.
		mixin (bitfields!(
			uint, "padSpcl",  spclPadBits,
			uint, "testSpcl", specialBits,
			bool, "signSpcl", signBit)
		);
		// Inf = infinities:
		//		payload, unused bits, infinitu bits and sign bit.
		mixin (bitfields!(
			uint, "padInf",  infPadBits,
			uint, "testInf", infinityBits,
			bool, "signInf", signBit)
		);
		// Nan = not-a-number: qNaN and sNan
		//		payload, unused bits, nan bits and sign bit.
		mixin (bitfields!(
			uint, "pyldNaN", payloadBits,
			uint, "padNaN",  nanPadBits,
			uint, "testNaN", nanBits,
			bool, "signNaN", signBit)
		);
	}

//--------------------------------
//	special bits
//--------------------------------

private:
	// The value of the (6) special bits when the number is a signaling NaN.
	immutable uint SIG_VAL = 0x3F;
	// The value of the (6) special bits when the number is a quiet NaN.
	immutable uint NAN_VAL = 0x3E;
	// The value of the (5) special bits when the number is infinity.
	immutable uint INF_VAL = 0x1E;

//--------------------------------
//	special values and constants
//--------------------------------

// TODO: this needs to be cleaned up -- SV is not the best name
private:
	static enum SV : uint
	{
		// The value corresponding to a positive signaling NaN.
		POS_SIG = 0x7E000000,
		// The value corresponding to a negative signaling NaN.
		NEG_SIG = 0xFE000000,

		// The value corresponding to a positive quiet NaN.
		POS_NAN = 0x7C000000,
		// The value corresponding to a negative quiet NaN.
		NEG_NAN = 0xFC000000,

		// The value corresponding to positive infinity.
		POS_INF = 0x78000000,
		// The value corresponding to negative infinity.
		NEG_INF = 0xF8000000,

		// The value corresponding to positive zero. (+0)
		POS_ZRO = 0x32800000,
		// The value corresponding to negative zero. (-0)
		NEG_ZRO = 0xB2800000,

		// The value of the largest representable positive number.
		POS_MAX = 0x77F8967F,
		// The value of the largest representable negative number.
		NEG_MAX = 0xF7F8967F,

        // common small integers
        POS_ONE = 0x32800001,
        NEG_ONE = 0xB2800001,
        POS_TWO = 0x32800002,
        NEG_TWO = 0xB2800002,
        POS_FIV = 0x32800005,
        NEG_FIV = 0xB2800005,
        POS_TEN = 0x3280000A,
        NEG_TEN = 0xB280000A,

		// pi and related values
        PI       = 0x2FAFEFD9,
        TAU      = 0x2FDFDFB2,
        PI_2 	 = 0x2F97F7EC,
        PI_SQR 	 = 0x6BF69924,
        SQRT_PI  = 0x2F9B0BA6,
        SQRT_2PI = 0x2F9B0BA6,
		// 1/PI
		// 1/SQRT_PI
		// 1/SQRT_2PI

        PHI     = 0x2F98B072,
        GAMMA   = 0x2F58137D,

        // logarithms
        E 		= 0x2FA97A4A,
		LOG2_E 	= 0x2F960387,
		LOG10_E = 0x2F4244A1,
        LN2 	= 0x2F69C410,
		LOG10_2 = 0x30007597,
        LN10 	= 0x2FA32279,
		LOG2_10 = 0x2FB2B048,

        // roots and squares of common values
        SQRT2   = 0x2F959446,
        SQRT1_2 = 0x2F6BE55C
	}

public:
    // special values
	immutable Dec32 NAN 	 = Dec32(SV.POS_NAN);
	immutable Dec32 SNAN	 = Dec32(SV.POS_SIG);
	immutable Dec32 INFINITY = Dec32(SV.POS_INF);
	immutable Dec32 NEG_INF  = Dec32(SV.NEG_INF);
	immutable Dec32 ZERO	 = Dec32(SV.POS_ZRO);
	immutable Dec32 NEG_ZERO = Dec32(SV.NEG_ZRO);
	immutable Dec32 MAX 	 = Dec32(SV.POS_MAX);
	immutable Dec32 NEG_MAX  = Dec32(SV.NEG_MAX);

    // small integers
	immutable Dec32 ONE 	 = Dec32(SV.POS_ONE);
	immutable Dec32 NEG_ONE  = Dec32(SV.NEG_ONE);
	immutable Dec32 TWO 	 = Dec32(SV.POS_TWO);
	immutable Dec32 NEG_TWO  = Dec32(SV.NEG_TWO);
	immutable Dec32 FIVE 	 = Dec32(SV.POS_FIV);
	immutable Dec32 NEG_FIVE = Dec32(SV.NEG_FIV);
	immutable Dec32 TEN 	 = Dec32(SV.POS_TEN);
	immutable Dec32 NEG_TEN  = Dec32(SV.NEG_TEN);

    // mathamatical constants
	immutable Dec32 TAU      = Dec32(SV.TAU);
	immutable Dec32 PI 	     = Dec32(SV.PI);
	immutable Dec32 PI_2 	 = Dec32(SV.PI_2);
	immutable Dec32 PI_SQR 	 = Dec32(SV.PI_SQR);
	immutable Dec32 SQRT_PI  = Dec32(SV.SQRT_PI);
	immutable Dec32 SQRT_2PI = Dec32(SV.SQRT_2PI);

	immutable Dec32 E 	     = Dec32(SV.E);
	immutable Dec32 LOG2_E 	 = Dec32(SV.LOG2_E);
	immutable Dec32 LOG10_E  = Dec32(SV.LOG10_E);
    immutable Dec32 LN2      = Dec32(SV.LN2);
	immutable Dec32 LOG10_2  = Dec32(SV.LOG10_2);
    immutable Dec32 LN10     = Dec32(SV.LN10);
	immutable Dec32 LOG2_10  = Dec32(SV.LOG2_10);
    immutable Dec32 SQRT2    = Dec32(SV.SQRT2);
    immutable Dec32 PHI      = Dec32(SV.PHI);
    immutable Dec32 GAMMA    = Dec32(SV.GAMMA);

    // boolean constants
    immutable Dec32 TRUE     = ONE;
    immutable Dec32 FALSE    = ZERO;

//--------------------------------
//	constructors
//--------------------------------

	/**
	 * Creates a Dec32 from a special value.
	 */
	private this(const SV sv) {
		intBits = sv;
	}

	// this unit test uses private values
	unittest {
		Dec32 num;
		num = Dec32(SV.POS_SIG);
		assertTrue(num.isSignaling);
		assertTrue(num.isNaN);
		assertTrue(!num.isNegative);
		assertTrue(!num.isNormal);
		num = Dec32(SV.NEG_SIG);
		assertTrue(num.isSignaling);
		assertTrue(num.isNaN);
		assertTrue(num.isNegative);
		assertTrue(!num.isNormal);
		num = Dec32(SV.POS_NAN);
		assertTrue(!num.isSignaling);
		assertTrue(num.isNaN);
		assertTrue(!num.isNegative);
		assertTrue(!num.isNormal);
		num = Dec32(SV.NEG_NAN);
		assertTrue(!num.isSignaling);
		assertTrue(num.isNaN);
		assertTrue(num.isNegative);
		assertTrue(num.isQuiet);
		num = Dec32(SV.POS_INF);
		assertTrue(num.isInfinite);
		assertTrue(!num.isNaN);
		assertTrue(!num.isNegative);
		assertTrue(!num.isNormal);
		num = Dec32(SV.NEG_INF);
		assertTrue(!num.isSignaling);
		assertTrue(num.isInfinite);
		assertTrue(num.isNegative);
		assertTrue(!num.isFinite);
		num = Dec32(SV.POS_ZRO);
		assertTrue(num.isFinite);
		assertTrue(num.isZero);
		assertTrue(!num.isNegative);
		assertTrue(num.isNormal);
		num = Dec32(SV.NEG_ZRO);
		assertTrue(!num.isSignaling);
		assertTrue(num.isZero);
		assertTrue(num.isNegative);
		assertTrue(num.isFinite);
	}

	/**
	 * Creates a Dec32 from a long integer.
	 */
	public this(const long n)
	{
		this = zero;
		signed = n < 0;
		coefficient = std.math.abs(n);
	}

	unittest {
real L10_2 = std.math.log10(2.0);
Dec32 LOG10_2 = Dec32(L10_2);
writeln("L10_2 = ", L10_2);
writeln("LOG10_2 = ", LOG10_2);
writeln("LOG10_2.toHexString = ", LOG10_2.toHexString);
real L2T = std.math.log2(10.0);
Dec32 LOG2_10 = Dec32(L2T);
writeln("L2T = ", L2T);
writeln("LOG2_10 = ", LOG2_10);
writeln("LOG2_10.toHexString = ", LOG2_10.toHexString);
    	Dec32 num;
		num = Dec32(1234567890L);
		assertTrue(num.toString == "1.234568E+9");
		num = Dec32(0);
		assertTrue(num.toString == "0");
		num = Dec32(1);
		assertTrue(num.toString == "1");
		num = Dec32(-1);
		assertTrue(num.toString == "-1");
		num = Dec32(5);
		assertTrue(num.toString == "5");
	}

	/**
	 * Creates a Dec32 from a boolean value.
	 */
	public this(const bool value)
	{
		this = zero;
        if (value) {
        	coefficient = 1;
        }
	}

	/**
	 * Creates a Dec32 from an unsigned integer and integer exponent.
	 */
	public this(const long mant, const int expo) {
		this(mant);
		exponent = exponent + expo;
	}

	unittest {
		Dec32 num;
		num = Dec32(1234567890L, 5);
		assertTrue(num.toString == "1.234568E+14");
		num = Dec32(0, 2);
		assertTrue(num.toString == "0E+2");
		num = Dec32(1, 75);
		assertTrue(num.toString == "1E+75");
		num = Dec32(-1, -75);
		assertTrue(num.toString == "-1E-75");
		num = Dec32(5, -3);
		assertTrue(num.toString == "0.005");
		num = Dec32(true, 1234567890L, 5);
		assertTrue(num.toString == "-1.234568E+14");
		num = Dec32(0, 0, 2);
		assertTrue(num.toString == "0E+2");
	}

	/**
	 * Creates a Dec32 from an unsigned integer and integer exponent.
	 */
	public this(const bool sign, const ulong mant, const int expo) {
		this(mant, expo);
		signed = sign;
	}

	unittest {
		Dec32 num;
		num = Dec32(1234567890L, 5);
		assertTrue(num.toString == "1.234568E+14");
		num = Dec32(0, 2);
		assertTrue(num.toString == "0E+2");
		num = Dec32(1, 75);
		assertTrue(num.toString == "1E+75");
		num = Dec32(-1, -75);
		assertTrue(num.toString == "-1E-75");
		num = Dec32(5, -3);
		assertTrue(num.toString == "0.005");
		num = Dec32(true, 1234567890L, 5);
		assertTrue(num.toString == "-1.234568E+14");
		num = Dec32(0, 0, 2);
		assertTrue(num.toString == "0E+2");
	}

	/**
	 * Creates a Dec32 from a BigDecimal
	 */
	public this(const BigDecimal num) {

		// check for special values
		if (num.isInfinite) {
			this = infinity(num.sign);
			return;
		}
		if (num.isQuiet) {
			this = nan();
			this.sign = num.sign;
			this.payload = num.payload;
			return;
		}
		if (num.isSignaling) {
			this = snan();
			this.sign = num.sign;
			this.payload = num.payload;
			return;
		}

		BigDecimal big = plus!BigDecimal(num, context32);

		if (big.isFinite) {
			this = zero;
			this.coefficient = cast(ulong)big.coefficient.toLong;
			this.exponent = big.exponent;
			this.sign = big.sign;
			return;
		}
		// check for special values
		if (big.isInfinite) {
			this = infinity(big.sign);
			return;
		}
		if (big.isSignaling) {
			this = snan();
			this.payload = big.payload;
			return;
		}
		if (big.isQuiet) {
			this = nan();
			this.payload = big.payload;
			return;
		}
		this = nan;
	}

   unittest {
		BigDecimal dec = 0;
		Dec32 num = dec;
		assertTrue(dec.toString == num.toString);
		dec = 1;
		num = dec;
		assertTrue(dec.toString == num.toString);
		dec = -1;
		num = dec;
		assertTrue(dec.toString == num.toString);
		dec = -16000;
		num = dec;
		assertTrue(dec.toString == num.toString);
		dec = uint.max;
		num = dec;
		assertTrue(num.toString == "4.294967E+9");
		assertTrue(dec.toString == "4294967295");
		dec = 9999999E+12;
		num = dec;
		assertTrue(dec.toString == num.toString);
	}

	/**
	 * Creates a Dec32 from a string.
	 */
	public this(const string str) {
		BigDecimal big = BigDecimal(str);
		this(big);
	}

	unittest {
		Dec32 num;
		num = Dec32("1.234568E+9");
		assertTrue(num.toString == "1.234568E+9");
		num = Dec32("NaN");
		assertTrue(num.isQuiet && num.isSpecial && num.isNaN);
		num = Dec32("-inf");
		assertTrue(num.isInfinite && num.isSpecial && num.isNegative);
	}

	/**
	 *	  Constructs a number from a real value.
	 */
	public this(const real r) {
		// check for special values
		if (!std.math.isFinite(r)) {
			this = std.math.isInfinity(r) ? INFINITY : NAN;
			this.sign = cast(bool)std.math.signbit(r);
			return;
		}
		// TODO: this won't do -- no rounding has occured.
		string str = format("%.*G", cast(int)context32.precision, r);
		this(str);
	}

	unittest {
		float f = 1.2345E+16f;
		Dec32 actual = Dec32(f);
		Dec32 expect = Dec32("1.2345E+16");
		assertEqual(expect,actual);
		real r = 1.2345E+16;
		actual = Dec32(r);
		expect = Dec32("1.2345E+16");
		assertEqual(expect,actual);
	}

	/**
	 * Copy constructor.
	 */
	public this(const Dec32 that) {
		this.bits = that.bits;
	}

	/**
	 * duplicator.
	 */
	const Dec32 dup() {
		return Dec32(this);
	}

//--------------------------------
//	properties
//--------------------------------

public:

	/// Returns the raw bits of this number.
	@property
	const uint bits() {
		return intBits;
	}

	/// Sets the raw bits of this number.
	@property
	uint bits(const uint raw) {
		intBits = raw;
		return intBits;
	}

	/// Returns the sign of this number.
	@property
	const bool sign() {
		return signed;
	}

	/// Sets the sign of this number and returns the sign.
	@property
	bool sign(const bool value) {
		signed = value;
		return signed;
	}

	/// Returns the exponent of this number.
	/// The exponent is undefined for infinities and NaNs: zero is returned.
	@property
	const int exponent() {
		if (this.isExplicit) {
			return expoEx - BIAS;
		}
		if (this.isImplicit) {
			return expoIm - BIAS;
		}
		// infinity or NaN.
		return 0;
	}

	unittest {
		Dec32 num;
		// reals
		num = std.math.PI;
		assertTrue(num.exponent == -6);
		num = 9.75E89;
		assertTrue(num.exponent == 87);
		// explicit
		num = 8388607;
		assertTrue(num.exponent == 0);
		// implicit
		num = 8388610;
		assertTrue(num.exponent == 0);
		num = 9.999998E23;
		assertTrue(num.exponent == 17);
		num = 9.999999E23;
		assertTrue(num.exponent == 17);
	}

	/// Sets the exponent of this number.
	/// If this number is infinity or NaN, this number is converted to
	/// a quiet NaN and the invalid operation flag is set.
	/// Otherwise, if the input value exceeds the maximum allowed exponent,
	/// this number is converted to infinity and the overflow flag is set.
	/// If the input value is less than the minimum allowed exponent,
	/// this number is converted to zero, the exponent is set to eTiny
	/// and the underflow flag is set.
	@property
	 int exponent(const int expo) {
		// check for overflow
		if (expo > context32.eMax) {
			this = signed ? NEG_INF : INFINITY;
			context32.setFlags(OVERFLOW);
			return 0;
		}
		// check for underflow
		if (expo < context32.eMin) {
			// if the exponent is too small even for a subnormal number,
			// the number is set to zero.
			if (expo < context32.eTiny) {
				this = signed ? NEG_ZERO : ZERO;
				expoEx = context32.eTiny + BIAS;
				context32.setFlags(SUBNORMAL);
				context32.setFlags(UNDERFLOW);
				return context32.eTiny;
			}
			// at this point the exponent is between eMin and eTiny.
			// NOTE: I don't think this needs special handling
		}
		// if explicit...
		if (this.isExplicit) {
			expoEx = expo + BIAS;
			return expoEx;
		}
		// if implicit...
		if (this.isFinite) {
			expoIm = expo + BIAS;
			return expoIm;
		}
		// if this point is reached the number is either infinity or NaN;
		// these have undefined exponent values.
		context32.setFlags(INVALID_OPERATION);
		this = nan;
		return 0;
	}

	unittest {
		Dec32 num;
		num = Dec32(-12000,5);
		num.exponent = 10;
		assertTrue(num.exponent == 10);
		num = Dec32(-9000053,-14);
		num.exponent = -27;
		assertTrue(num.exponent == -27);
		num = infinity;
		assertTrue(num.exponent == 0);
	}

	/// Returns the coefficient of this number.
	/// The exponent is undefined for infinities and NaNs: zero is returned.
	@property
	const uint coefficient() {
		if (this.isExplicit) {
			return mantEx;
		}
		if (this.isFinite) {
			return mantIm | (0b100 << implicitBits);
		}
		// Infinity or NaN.
		return 0;
	}

	// Sets the coefficient of this number. This may cause an
	// explicit number to become an implicit number, and vice versa.
	@property
	uint coefficient(const ulong mant) {
		// if not finite, convert to NaN and return 0.
		if (!this.isFinite) {
			this = nan;
			context32.setFlags(INVALID_OPERATION);
			return 0;
		}
		ulong copy = mant;
		if (copy > C_MAX_IMPLICIT) {
			int expo = 0;
			uint digits = numDigits(copy);
			expo = setExponent(sign, copy, digits, context32);
			if (this.isExplicit) {
				expoEx = expoEx + expo;
			}
			else {
				expoIm = expoIm + expo;
			}
		}
		// at this point, the number <= C_MAX_IMPLICIT
		if (copy <= C_MAX_EXPLICIT) {
			// if implicit, convert to explicit
			if (this.isImplicit) {
				expoEx = expoIm;
			}
			mantEx = cast(uint)copy;
			return mantEx;
		}
		else {	// copy <= C_MAX_IMPLICIT
			// if explicit, convert to implicit
			if (this.isExplicit) {
				expoIm = expoEx;
				testIm = 0x3;
			}
			mantIm = cast(uint)copy & C_IMPLICIT_MASK;
			return mantIm | (0b100 << implicitBits);
		}
	}

	unittest {
		Dec32 num;
		assertTrue(num.coefficient == 0);
		num = 9.998743;
		assertTrue(num.coefficient == 9998743);
		num = Dec32(9999213,-6);
		assertTrue(num.coefficient == 9999213);
		num = -125;
		assertTrue(num.coefficient == 125);
		num = -99999999;
		assertTrue(num.coefficient == 1000000);
	}

	/// Returns the number of digits in this number's coefficient.
	@property
	const int digits() {
		return numDigits(this.coefficient);
	}

	/// Has no effect.
	@property
	const int digits(const int digs) {
		return digits;
	}

	/// Returns the payload of this number.
	/// If this is a NaN, returns the value of the payload bits.
	/// Otherwise returns zero.
	@property
	const uint payload() {
		if (this.isNaN) {
			return pyldNaN;
		}
		return 0;
	}

	/// Sets the payload of this number.
	/// If the number is not a NaN (har!) no action is taken and zero
	/// is returned.
	@property
	uint payload(const uint value) {
		if (isNaN) {
			pyldNaN = value;
			return pyldNaN;
		}
		return 0;
	}

	unittest {
		Dec32 num;
		assertTrue(num.payload == 0);
		num = snan;
		assertTrue(num.payload == 0);
		num.payload = 234;
		assertTrue(num.payload == 234);
		assertTrue(num.toString == "sNaN234");
		num = 1234567;
		assertTrue(num.payload == 0);
	}

//--------------------------------
//	constants
//--------------------------------

	static Dec32 zero(const bool signed = false) {
		return signed ? NEG_ZERO : ZERO;
	}

	static Dec32 max(const bool signed = false) {
		return signed ? NEG_MAX : MAX;
	}

	static Dec32 infinity(const bool signed = false) {
		return signed ? NEG_INF : INFINITY;
	}

	static Dec32 nan(const uint payload = 0) {
		if (payload) {
			Dec32 result = NAN;
			result.payload = payload;
			return result;
		}
		return NAN;
	}

	static Dec32 snan(const uint payload = 0) {
		if (payload) {
			Dec32 result = SNAN;
			result.payload = payload;
			return result;
		}
		return SNAN;
	}

	// floating point properties
	static Dec32 init() 	  { return NAN; }
	static Dec32 epsilon()	  { return Dec32(1, -7); }
	static Dec32 min_normal() { return Dec32(1, context32.eMin); }
	static Dec32 min()		  { return Dec32(1, context32.eTiny); }

	static int dig()		{ return 7; }
	static int mant_dig()	{ return 24; }
	static int max_10_exp() { return context32.eMax; }
	static int min_10_exp() { return context32.eMin; }
	static int max_exp()	{ return cast(int)(context32.eMax/LOG2); }
	static int min_exp()	{ return cast(int)(context32.eMin/LOG2); }

	/// Returns the maximum number of decimal digits in this context.
	static uint precision(DecimalContext context = context32) {
		return context.precision;
	}

	/// Returns the maximum number of decimal digits in this context.
	static uint dig(DecimalContext context = context32) {
		return context.precision;
	}

/*	/// Returns the number of binary digits in this context.
	static uint mant_dig(DecimalContext context = context32) {
		return cast(int)context.mant_dig;
	}

	static int min_exp(DecimalContext context = context32) {
		return context.min_exp;
	}

	static int max_exp(DecimalContext context = context32) {
		return context.max_exp;
	}*/

	/// Returns the minimum representable normal value in this context.
	static Dec32 min_normal(DecimalContext context = context32) {
		return Dec32(1, context.eMin);
	}

	/// Returns the minimum representable subnormal value in this context.
	/// NOTE: Creation of this number will not set the
	/// subnormal flag until it is used. The operations will
	/// set the flags as needed.
	static Dec32 min(DecimalContext context = context32) {
		return Dec32(1, context.eTiny);
	}

	/// returns the smallest available increment to 1.0 in this context
	static Dec32 epsilon(DecimalContext context = context32) {
		return Dec32(1, -context.precision);
	}

	static int min_10_exp(DecimalContext context = context32) {
		return context.eMin;
	}

	static int max_10_exp(DecimalContext context = context32) {
		return context.eMax;
	}

//--------------------------------
//	classification properties
//--------------------------------

	/**
	 * Returns true if this number's representation is canonical.
	 * Finite numbers are always canonical.
	 * Infinities and NaNs are canonical if their unused bits are zero.
	 */
	const bool isCanonical() {
		if (isInfinite) return padInf == 0;
		if (isNaN) return signed == 0 && padNaN == 0;
		// finite numbers are always canonical
		return true;
	}

	/**
	 * Returns true if this number's representation is canonical.
	 * Finite numbers are always canonical.
	 * Infinities and NaNs are canonical if their unused bits are zero.
	 */
	const Dec32 canonical() {
		Dec32 copy = this;
		if (this.isCanonical) return copy;
		if (this.isInfinite) {
			copy.padInf = 0;
			return copy;
		}
		else { /* isNaN */
			copy.signed = 0;
			copy.padNaN = 0;
			return copy;
		}
	}

	/**
	 * Returns true if this number is +\- zero.
	 */
	const bool isZero() {
		return isExplicit && mantEx == 0;
	}

	/**
	 * Returns true if the coefficient of this number is zero.
	 */
	const bool coefficientIsZero() {
		return coefficient == 0;
	}

	/**
	 * Returns true if this number is a quiet or signaling NaN.
	 */
	const bool isNaN() {
		return testNaN == NAN_VAL || testNaN == SIG_VAL;
	}

	/**
	 * Returns true if this number is a signaling NaN.
	 */
	const bool isSignaling() {
		return testNaN == SIG_VAL;
	}

	/**
	 * Returns true if this number is a quiet NaN.
	 */
	const bool isQuiet() {
		return testNaN == NAN_VAL;
	}

	/**
	 * Returns true if this number is +\- infinity.
	 */
	const bool isInfinite() {
		return testInf == INF_VAL;
	}

	/**
	 * Returns true if this number is neither infinite nor a NaN.
	 */
	const bool isFinite() {
		return testSpcl != 0xF;
	}

	/**
	 * Returns true if this number is a NaN or infinity.
	 */
	const bool isSpecial() {
		return testSpcl == 0xF;
	}

	const bool isExplicit() {
		return testIm != 0x3;
	}

	const bool isImplicit() {
		return testIm == 0x3 && testSpcl != 0xF;
	}

	/**
	 * Returns true if this number is negative. (Includes -0)
	 */
	const bool isSigned() {
		return signed;
	}

	const bool isNegative() {
		return signed;
	}

    const bool isTrue() {
        return coefficient != 0;
    }

    const bool isFalse() {
        return coefficient == 0;
    }

    const bool isZeroCoefficient() {
        return coefficient == 0;
    }
	/**
	 * Returns true if this number is subnormal.
	 */
	const bool isSubnormal(DecimalContext context = context32) {
		if (isSpecial) return false;
		return adjustedExponent < context.eMin;
	}

	/**
	 * Returns true if this number is normal.
	 */
	const bool isNormal(DecimalContext context = context32) {
		if (isSpecial) return false;
		return adjustedExponent >= context.eMin;
	}

	/**
	 * Returns the value of the adjusted exponent.
	*/
	const int adjustedExponent() {
		return exponent + digits - 1;
	}

//--------------------------------
//	conversions
//--------------------------------

	/**
	 * Converts a Dec32 to a BigDecimal
	 */
	const BigDecimal toBigDecimal() {
		if (isFinite) {
			return BigDecimal(sign, BigInt(coefficient), exponent);
		}
		if (isInfinite) {
			return BigDecimal.infinity(sign);
		}
		// number is a NaN
		BigDecimal dec;
		if (isQuiet) {
			dec = BigDecimal.nan(sign);
		}
		if (isSignaling) {
			dec = BigDecimal.snan(sign);
		}
		if (payload) {
			dec.payload(payload);
		}
		return dec;
	}

	unittest {
		Dec32 num = Dec32("12345E+17");
		BigDecimal expected = BigDecimal("12345E+17");
		BigDecimal actual = num.toBigDecimal;
		assertTrue(actual == expected);
	}

	const int toInt() {
		int n;
		if (isNaN) {
			context32.setFlags(INVALID_OPERATION);
			return 0;
		}
		if (this > Dec32(int.max) || (isInfinite && !isSigned)) return int.max;
		if (this < Dec32(int.min) || (isInfinite &&  isSigned)) return int.min;
		quantize!Dec32(this, ONE, context32);
		n = coefficient;
		return signed ? -n : n;
	}

	unittest {
		Dec32 num;
		num = 12345;
		assertTrue(num.toInt == 12345);
		num = 1.0E6;
		assertTrue(num.toInt == 1000000);
		num = -1.0E60;
		assertTrue(num.toInt == int.min);
		num = NEG_INF;
		assertTrue(num.toInt == int.min);
	}

	const long toLong() {
		long n;
		if (isNaN) {
			context32.setFlags(INVALID_OPERATION);
			return 0;
		}
		if (this > long.max || (isInfinite && !isSigned)) return long.max;
		if (this < long.min || (isInfinite &&  isSigned)) return long.min;
		quantize!Dec32(this, ONE, context32);
		n = coefficient;
		return signed ? -n : n;
	}

	unittest {
		Dec32 num;
		num = -12345;
		assertTrue(num.toLong == -12345);
		num = 2 * int.max;
		assertTrue(num.toLong == 2 * int.max);
		num = 1.0E6;
		assertTrue(num.toLong == 1000000);
		num = -1.0E60;
		assertTrue(num.toLong == long.min);
		num = NEG_INF;
		assertTrue(num.toLong == long.min);
	}

	/**
	 * Converts this number to an exact scientific-style string representation.
	 */
	const string toSciString() {
		return decimal.conv.toSciString!Dec32(this);
	}

	/**
	 * Converts this number to an exact engineering-style string representation.
	 */
	const string toEngString() {
		return decimal.conv.toEngString!Dec32(this);
	}

	/**
	 * Converts a Dec32 to a string
	 */
	const public string toString() {
		 return toSciString();
	}

	unittest {
		string str;
		str = "-12.345E-42";
		Dec32 num = Dec32(str);
		assertTrue(num.toString == "-1.2345E-41");
	}

	/**
	 * Creates an exact representation of this number.
	 */
/*	  const string toExact()
	{
		if (this.isFinite) {
			return format("%s%07dE%s%02d", signed ? "-" : "+", coefficient,
					exponent < 0 ? "-" : "+", exponent);
		}
		if (this.isInfinite) {
			return format("%s%s", signed ? "-" : "+", "Infinity");
		}
		if (this.isQuiet) {
			if (payload) {
				return format("%s%s%d", signed ? "-" : "+", "NaN", payload);
			}
			return format("%s%s", signed ? "-" : "+", "NaN");
		}
		// this.isSignaling
		if (payload) {
			return format("%s%s%d", signed ? "-" : "+", "sNaN", payload);
		}
		return format("%s%s", signed ? "-" : "+", "sNaN");
	}*/
	const string toExact() {
		return decimal.conv.toExact!Dec32(this);
	}


	unittest {
		Dec32 num;
		assertTrue(num.toExact == "+NaN");
		num = max;
		assertTrue(num.toExact == "+9999999E+90");
		num = 1;
		assertTrue(num.toExact == "+1E+00");
		num = C_MAX_EXPLICIT;
		assertTrue(num.toExact == "+8388607E+00");
		num = infinity(true);
		assertTrue(num.toExact == "-Infinity");
	}

	/**
	 * Creates an abstract representation of this number.
	 */
	const string toAbstract()
	{
		if (this.isFinite) {
			return format("[%d,%s,%d]", signed ? 1 : 0, coefficient, exponent);
		}
		if (this.isInfinite) {
			return format("[%d,%s]", signed ? 1 : 0, "inf");
		}
		if (this.isQuiet) {
			if (payload) {
				return format("[%d,%s,%d]", signed ? 1 : 0, "qNaN", payload);
			}
			return format("[%d,%s]", signed ? 1 : 0, "qNaN");
		}
		// this.isSignaling
		if (payload) {
			return format("[%d,%s,%d]", signed ? 1 : 0, "sNaN", payload);
		}
		return format("[%d,%s]", signed ? 1 : 0, "sNaN");
	}

	unittest {
		Dec32 num;
		num = Dec32("-25.67E+2");
		assertTrue(num.toAbstract == "[1,2567,0]");
	}

	/**
	 * Converts this number to a hexadecimal string representation.
	 */
	const string toHexString() {
		 return format("0x%08X", bits);
	}

	/**
	 * Converts this number to a binary string representation.
	 */
	const string toBinaryString() {
		return format("%0#32b", bits);
	}

	unittest {
		Dec32 num = 12345;
		assertTrue(num.toHexString == "0x32803039");
		assertTrue(num.toBinaryString == "00110010100000000011000000111001");
	}

//--------------------------------
//	comparison
//--------------------------------

	/**
	 * Returns -1, 0 or 1, if this number is less than, equal to or
	 * greater than the argument, respectively.
	 */
	const int opCmp(T:Dec32)(const T that) {
		return compare!Dec32(this, that, context32);
	}

	/**
	 * Returns -1, 0 or 1, if this number is less than, equal to or
	 * greater than the argument, respectively.
	 */
	const int opCmp(T)(const T that) if(isPromotable!T){
		return opCmp!Dec32(Dec32(that));
	}

	unittest {
		Dec32 a, b;
		a = Dec32(104.0);
		b = Dec32(105.0);
		assertTrue(a < b);
		assertTrue(b > a);
	}

	/**
	 * Returns true if this number is equal to the specified number.
	 */
	const bool opEquals(T:Dec32)(const T that) {
		// quick bitwise check
		if (this.bits == that.bits) {
			if (this.isFinite) return true;
			if (this.isInfinite) return true;
			if (this.isQuiet) return false;
			// let the main routine handle the signaling NaN
		}
		return equals!Dec32(this, that, context32);
	}

	unittest {
		Dec32 a, b;
		a = Dec32(105);
		b = Dec32(105);
		assertTrue(a == b);
	}
	/**
	 * Returns true if this number is equal to the specified number.
	 */
	const bool opEquals(T)(const T that) if(isPromotable!T) {
		return opEquals!Dec32(Dec32(that));
	}

	unittest {
		Dec32 a, b;
		a = Dec32(105);
		b = Dec32(105);
		int c = 105;
		assertTrue(a == c);
		real d = 105.0;
		assertTrue(a == d);
		assertTrue(a == 105);
	}

	const bool isIdentical(const Dec32 that) {
		return this.bits == that.bits;
	}

//--------------------------------
// assignment
//--------------------------------

	// (7) UNREADY: opAssign(T: Dec32)(const Dec32). Flags. Unit Tests.
	/// Assigns a Dec32 (copies that to this).
	void opAssign(T:Dec32)(const T that) {
		this.intBits = that.intBits;
	}

	unittest {
		Dec32 rhs, lhs;
		rhs = Dec32(270E-5);
		lhs = rhs;
		assertTrue(lhs == rhs);
	}

	// (7) UNREADY: opAssign(T)(const T). Flags.
	///    Assigns a numeric value.
	void opAssign(T)(const T that) {
		this = Dec32(that);
	}

	unittest {
		Dec32 rhs;
		rhs = 332089;
		assertTrue(rhs.toString == "332089");
		rhs = 3.1415E+3;
		assertTrue(rhs.toString == "3141.5");
	}

//--------------------------------
// unary operators
//--------------------------------

	const Dec32 opUnary(string op)()
	{
		static if (op == "+") {
			return plus!Dec32(this, context32);
		}
		else static if (op == "-") {
			return minus!Dec32(this, context32);
		}
		else static if (op == "++") {
			return add!Dec32(this, Dec32(1), context32);
		}
		else static if (op == "--") {
			return subtract!Dec32(this, Dec32(1), context32);
		}
	}

	unittest {
		Dec32 num, actual, expect;
		num = 134;
		expect = num;
		actual = +num;
		assertTrue(actual == expect);
		num = 134.02;
		expect = -134.02;
		actual = -num;
		assertTrue(actual == expect);
		num = 134;
		expect = 135;
		actual = ++num;
		assertTrue(actual == expect);
		num = 1.00E12;
		expect = num;
		actual = --num;
		assertEqual(expect,actual);
		actual = num--;
		assertEqual(expect,actual);
		num = 1.00E12;
		expect = num;
		actual = ++num;
		assertEqual(expect,actual);
		actual = num++;
		assertTrue(actual == expect);
		num = Dec32(9999999, 90);
		expect = num;
		actual = num++;
		assertTrue(actual == expect);
		num = 12.35;
		expect = 11.35;
		actual = --num;
		assertTrue(actual == expect);
	}

//--------------------------------
// binary operators
//--------------------------------

	const T opBinary(string op, T:Dec32)(const T rhs)
	{
		static if (op == "+") {
			return add!Dec32(this, rhs, context32);
		}
		else static if (op == "-") {
			return subtract!Dec32(this, rhs, context32);
		}
		else static if (op == "*") {
			return multiply!Dec32(this, rhs, context32);
		}
		else static if (op == "/") {
			return divide!Dec32(this, rhs, context32);
		}
		else static if (op == "%") {
			return remainder!Dec32(this, rhs, context32);
		}
		else static if (op == "&") {
			return and!Dec32(this, rhs, context32);
		}
		else static if (op == "|") {
			return or!Dec32(this, rhs, context32);
		}
		else static if (op == "^") {
			return xor!Dec32(this, rhs, context32);
		}
	}

	unittest {
		Dec32 op1, op2, actual, expect;
		op1 = 4;
		op2 = 8;
		actual = op1 + op2;
		expect = 12;
		assertEqual(expect,actual);
		actual = op1 - op2;
		expect = -4;
		assertEqual(expect,actual);
		actual = op1 * op2;
		expect = 32;
		assertEqual(expect,actual);
		op1 = 5;
		op2 = 2;
		actual = op1 / op2;
		expect = 2.5;
		assertEqual(expect,actual);
		op1 = 10;
		op2 = 3;
		actual = op1 % op2;
		expect = 1;
		assertEqual(expect,actual);
		op1 = Dec32("101");
		op2 = Dec32("110");
		actual = op1 & op2;
		expect = 100;
		assertEqual(expect,actual);
		actual = op1 | op2;
		expect = 111;
		assertEqual(expect,actual);
		actual = op1 ^ op2;
		expect = 11;
		assertEqual(expect,actual);
	}

	/**
	 * Detect whether T is promotable to decimal32 type.
	 */
	private template isPromotable(T) {
		enum bool isPromotable = is(T:ulong) || is(T:real);
	}

	const Dec32 opBinary(string op, T)(const T rhs) if(isPromotable!T)
	{
		return opBinary!(op,Dec32)(Dec32(rhs));
	}

	unittest {
		Dec32 num = Dec32(591.3);
		Dec32 result = num * 5;
		assertTrue(result == Dec32(2956.5));
	}

//-----------------------------
// operator assignment
//-----------------------------

	ref Dec32 opOpAssign(string op, T:Dec32) (T rhs) {
		this = opBinary!op(rhs);
		return this;
	}

	ref Dec32 opOpAssign(string op, T) (T rhs) if (isPromotable!T) {
		this = opBinary!op(rhs);
		return this;
	}

	unittest {
		Dec32 op1, op2, actual, expect;
		op1 = 23.56;
		op2 = -2.07;
		op1 += op2;
		expect = 21.49;
		actual = op1;
		assertEqual(expect,actual);
		op1 *= op2;
		expect = -44.4843;
		actual = op1;
		assertEqual(expect,actual);
		op1 = 95;
		op1 %= 90;
		actual = op1;
		expect = 5;
		assertEqual(expect,actual);
	}

	/**
	 * Returns uint ten raised to the specified power.
	 */
	static uint pow10(const int n) {
		return 10U^^n;
	}

	unittest {
		int n;
		n = 3;
		assertTrue(pow10(n) == 1000);
	}

}	// end Dec32 struct

public real toReal(Dec32 arg) {
	string str = arg.toSciString;
	return to!real(str);
}

/*  NOTE: this causes a compiler error whereas the code above doesn't. Bug?
public real toReal(Dec32 arg) {
	string str = arg.toSciString;
	return to!real(str);
}
*/

unittest {
	write("toReal...");
	writeln("test missing");
}

public Dec32 exp(Dec32 arg) {
	if (arg.isNaN) {
		return Dec32.NAN;
	}
 	if (arg.isInfinite) {
	 	if (arg.isNegative) {
			return Dec32.ZERO;
		}
		else {
			return Dec32.INFINITY;
		}
	}
	if (arg.isZero) {
		return Dec32.ONE;
	}
	return Dec32(std.math.exp(toReal(arg)));
}

unittest {
	write("exp...");
	writeln("test missing");
}

public Dec32 ln(Dec32 arg) {
	if (arg.isNegative || arg.isNaN) {
		// set invalid op flag(?)
		return Dec32.NAN;
	}
 	if (arg.isInfinite) {
		return Dec32.INFINITY;
	}
	if (arg.isZero) {
		return Dec32.NEG_INF;
	}
	if (arg == Dec32.ONE) {
		return Dec32.ZERO;
	}
	// TODO: check for a NaN? or special value?
	return Dec32(std.math.log(toReal(arg)));
}

unittest {
	write("ln...");
	writeln("test missing");
}

public Dec32 log10(Dec32 arg) {
	if (arg.isNegative || arg.isNaN) {
		// set invalid op flag(?)
		return Dec32.NAN;
	}
 	if (arg.isInfinite) {
		return Dec32.INFINITY;
	}
	if (arg.isZero) {
		return Dec32.NEG_INF;
	}
	if (arg == Dec32.ONE) {
		return Dec32.ZERO;
	}
	// TODO: check for a NaN? or special value?
	return Dec32(std.math.log10(toReal(arg)));
}

unittest {
	write("log10...");
	writeln("test missing");
}

unittest {
	writeln("-------------------");
	writeln("dec32...........end");
	writeln("-------------------");
}


