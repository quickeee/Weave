/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.compiler
{
	import flash.system.ApplicationDomain;
	import flash.utils.Dictionary;
	import flash.utils.describeType;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
	
	import mx.utils.ObjectUtil;
	import mx.utils.StringUtil;
	
	import weave.core.ClassUtils;
	import weave.core.StageUtils;
	
	/**
	 * This class provides a static function compileToFunction() that compiles an expression String into a Function.
	 * 
	 * @author adufilie
	 */
	public class Compiler
	{
		public static var debug:Boolean = false;
		
		{ /** begin static code block **/
			initStaticObjects();
			includeLibraries(Math, StringUtil, StandardLib);
			
			//StageUtils.callLater(null, test);
		} /** end static code block **/
		
		/**
		 * This function compiles an expression into a Function that evaluates using variables from a symbolTable.
		 * Strings may be surrounded by quotation marks (") and literal quotation marks are escaped by two quote marks together ("").
		 * The escape sequence for a quoted variable name to indicate a quotation mark is two quotation marks together.
		 * @param expression An expression to compile.
		 * @param symbolTable This is either a function that returns a variable by name or a lookup table containing custom variables and functions that can be used in the expression.  These values may be changed after compiling.
		 * @return A Function generated from the expression String, or null if the String does not represent a valid expression.
		 */
		public static function compileToFunction(expression:String, symbolTable:Object):Function
		{
			var tokens:Array = getTokens(expression);
			//trace("source:", expression, "tokens:" + tokens.join(' '));
			var compiledObject:ICompiledObject = compileTokens(tokens);
			return compileObjectToFunction(compiledObject, symbolTable);
		}
		
		/**
		 * This function will compile an expression into a compiled object representing a function that takes no parameters and returns a value.
		 * This function is useful for inspecting the structure of the compiled function and decompiling individual parts.
		 * @param expression An expression to parse.
		 * @return A CompiledConstant or CompiledFunctionCall generated from the tokens, or null if the tokens do not represent a valid expression.
		 */
		public static function compileToObject(expression:String):ICompiledObject
		{
			return compileTokens(getTokens(expression));
		}
		
		// TODO: add option to make resulting function throw an error instead of returning undefined
		// TODO: includeLibrary(sourceSymbolTable, destinationSymbolTable) where it copies all the properties of source to destination
		
		/**
		 * This function will include additional libraries to be supported by the compiler when compiling functions.
		 * @param classesOrObjects An Array of Class definitions or objects containing functions to be supported by the compiler.
		 */		
		public static function includeLibraries(...classesOrObjects):void
		{
			for (var i:int = 0; i < classesOrObjects.length; i++)
			{
				var library:Object = classesOrObjects[i];
				// only add this library to the list if it is not already added.
				if (library != null && libraries.indexOf(library) < 0)
				{
					libraries.push(library);
					
					if (library is Class)
					{
						// save the class name as a symbol
						var className:String = getQualifiedClassName(library);
						className = className.split('.').pop();
						className = className.split(':').pop();
						constants[className] = library;
					}
					// save mappings to all constants and methods in the library
					var classInfo:XML = describeType(library);
					for each (var constantName:String in classInfo.child("constant").attribute("name"))
						constants[constantName] = library[constantName];
					for each (var methodName:String in classInfo.child("method").attribute("name"))
						constants[methodName] = library[methodName];
				}
			}
		}
		
		/**
		 * This function will add a variable to the constants available in expressions.
		 * @param constantName The name of the constant.
		 * @param constantValue The value of the constant.
		 */		
		public static function includeConstant(constantName:String, constantValue:*):void
		{
			constants[constantName] = constantValue;
		}

		/**
		 * This function gets a list of all the libraries currently being used by the compiler.
		 * @return A new Array containing a list of all the objects and/or classes used as libraries in the compiler.
		 */		
		public static function getAllLibraries():Array
		{
			return libraries.concat(); // make a copy
		}
		
		/**
		 * While this is set to true, compiler optimizations are enabled.
		 */		
		private static var enableOptimizations:Boolean = true;
		
		/**
		 * This is a list of objects and/or classes containing functions and constants supported by the compiler.
		 */
		private static const libraries:Array = [];
		
		/**
		 * This is the prefix used for the function notation of infix operators.
		 * For example, the function notation for ( x + y ) is ( operator+(x,y) ).
		 */
		public static const OPERATOR_PREFIX:String = 'operator';
		
		/**
		 * This is a String containing all the characters that are treated as whitespace.
		 */
		private static const WHITESPACE:String = '\r\n \t\f';
		/**
		 * This is the maximum allowed length of an operator.
		 */		
		private static const MAX_OPERATOR_LENGTH:int = 4;
		/**
		 * This is used to match number tokens.
		 */		
		private static const numberRegex:RegExp = /^(0x[0-9A-F]+|[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)/;
		/**
		 * This object maps the name of a predefined constant to its value.
		 */
		private static var constants:Object = null;
		/**
		 * This object maps an operator like "*" to a Function with the following signature:
		 *     function(x:Number, y:Number):Number
		 * If there is no function associated with the operator, it maps the operator to a value of null.
		 */
		private static var operators:Object = null;
		/**
		 * This object maps an assignment operator like "=" to its corresponding function.
		 * This object is used as a quick lookup to see if an operator is an assignment operator.
		 */
		private static var assignmentOperators:Object = null;
		/**
		 * This is a two-dimensional Array of operator symbols arranged in the order they should be evaluated.
		 * Each nested Array is a group of operators that should be evaluated in the same pass.
		 */
		private static var orderedOperators:Array = null;
		/**
		 * This is an Array of all the unary operator symbols.
		 */
		private static var unaryOperatorSymbols:Array = null;
		/**
		 * This function will initialize the operators, constants, and functions.
		 */
		private static function initStaticObjects():void
		{
			constants = new Object();
			operators = new Object();
			assignmentOperators = new Object();
			
			// add built-in functions
			constants['iif'] = function(c:*, t:*, f:*):* { return c ? t : f; };
			constants['typeof'] = function(value:*):* { return typeof(value); };
			constants['trace'] = function(...args):void {
				// for trace debugging, debug must be set to true
				if (debug)
					trace.apply(null, args);
			};
			
			// add constants
			constants['isNaN'] = isNaN;
			constants['isFinite'] = isFinite;
			constants["undefined"] = undefined;
			constants["null"] = null;
			constants["NaN"] = NaN;
			constants["true"] = true;
			constants["false"] = false;
			constants["Infinity"] = Infinity;
			constants['Number'] = Number;
			constants['String'] = String;
			constants['Boolean'] = Boolean;
			constants['Array'] = Array;

			/** operators **/
			// first, make sure all special characters are defined as operators whether or not they have functions associated with them
			var specialChars:String = "~!#%^&*()-+=[{]}\\;:'\",<.>/?";
			for (var i:int = 0; i < specialChars.length; i++)
				operators[specialChars.charAt(i)] = true;
			// now define the functions
			// property access
			operators["."] = function(object:*, ...chain):* {
				for (var i:int = 0; i < chain.length; i++)
					object = object[chain[i]];
				return object;
			};
			// array creation
			operators["[]"] = function(...args):* { return args; };
			// math
			operators["**"] = Math.pow;
			operators["*"] = function(x:*, y:*):Number { return x * y; };
			operators["/"] = function(x:*, y:*):Number { return x / y; };
			operators["%"] = function(x:*, y:*):Number { return x % y; };
			operators["+"] = function(x:*, y:*):* { return x + y; }; // also works for strings
			operators["-"] = function(...args):* {
				// this works as a unary or infix operator
				if (args.length == 1)
					return -args[0];
				if (args.length == 2)
					return args[0] - args[1];
			};
			// bitwise
			operators["~"] = function(x:*):* { return ~x; };
			operators["&"] = function(x:*, y:*):* { return x & y; };
			operators["|"] = function(x:*, y:*):* { return x | y; };
			operators["^"] = function(x:*, y:*):* { return x ^ y; };
			operators["<<"] = function(x:*, y:*):* { return x << y; };
			operators[">>"] = function(x:*, y:*):* { return x >> y; };
			operators[">>>"] = function(x:*, y:*):* { return x >>> y; };
			// comparison
			operators["<"] = function(x:*, y:*):Boolean { return x < y; };
			operators["<="] = function(x:*, y:*):Boolean { return x <= y; };
			operators[">"] = function(x:*, y:*):Boolean { return x > y; };
			operators[">="] = function(x:*, y:*):Boolean { return x >= y; };
			operators["=="] = function(x:*, y:*):Boolean { return x == y; };
			operators["==="] = function(x:*, y:*):Boolean { return x === y; };
			operators["!="] = function(x:*, y:*):Boolean { return x != y; };
			operators["!=="] = function(x:*, y:*):Boolean { return x !== y; };
			// logic
			operators["!"] = function(x:*):Boolean { return !x; };
			operators["&&"] = function(x:*, y:*):* { return x && y; };
			operators["||"] = function(x:*, y:*):* { return x || y; };
			// branching
			operators["?:"] = constants['iif'];
			// multiple commands
			operators[','] = function(...args):* { return args[args.length - 1]; };
			//assignment operators -- first param becomes the parent, and the two remaining args are propertyName and value
			assignmentOperators['=']    = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] =    a[i + 1]; };
			assignmentOperators['+=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] +=   a[i + 1]; };
			assignmentOperators['-=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] -=   a[i + 1]; };
			assignmentOperators['*=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] *=   a[i + 1]; };
			assignmentOperators['/=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] /=   a[i + 1]; };
			assignmentOperators['%=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] %=   a[i + 1]; };
			assignmentOperators['<<=']  = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] <<=  a[i + 1]; };
			assignmentOperators['>>=']  = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] >>=  a[i + 1]; };
			assignmentOperators['>>>='] = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] >>>= a[i + 1]; };
			assignmentOperators['&=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] &=   a[i + 1]; };
			assignmentOperators['^=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] ^=   a[i + 1]; };
			assignmentOperators['|=']   = function(o:*, ...a):* { for (var i:int = 0; i < a.length - 2; i++) o = o[a[i]]; return o[a[i]] |=   a[i + 1]; };
			for (var aop:String in assignmentOperators)
				operators[aop] = assignmentOperators[aop];
			
			// evaluate operators in the same order as ActionScript
			orderedOperators = [
				['*','/','%'],
				['+','-'],
				['<<','>>','>>>'],
				['<','<=','>','>='],
				['==','!=','===','!=='],
				['&'],
				['^'],
				['|'],
				['&&'],
				['||']
			];
			// unary operators
			unaryOperatorSymbols = ['#','-','~','!'];

			// create a corresponding function name for each operator
			for (var op:String in operators)
				if (operators[op] is Function)
					constants[OPERATOR_PREFIX + op] = operators[op];
		}

		/**
		 * @param expression An expression string to parse.
		 * @return An Array containing all the tokens found in the expression.
		 */
		private static function getTokens(expression:String):Array
		{
			var tokens:Array = [];
			var n:int = expression.length;
			// get a flat list of tokens
			var i:int = 0;
			while (i < n)
			{
				var token:String = getToken(expression, i);
				if (WHITESPACE.indexOf(token.charAt(0)) == -1)
					tokens.push(token);
				i += token.length;
			}
			return tokens;
		}
		/**
		 * This function is for internal use only.
		 * @param expression An expression to parse.
		 * @param index The starting index of the token.
		 * @return The token beginning at the specified index, or null if an invalid quoted string was found.
		 */
		private static function getToken(expression:String, index:int):String
		{
			var endIndex:int;
			var n:int = expression.length;
			var c:String = expression.charAt(index);
			
			// handle quoted string
			if (c == '"' || c == "'")
			{
				var quote:String = c;
				// index points to the opening quote
				// make endIndex point to the matching end quote
				for (c = null, endIndex = index + 1; endIndex < n; endIndex++)
				{
					c = expression.charAt(endIndex);
					// stop when matching quote found, unless there are two together for an escape sequence
					if (c == quote)
					{
						if (endIndex < n - 1 && expression.charAt(endIndex + 1) == quote)
						{
							// skip second quote
							endIndex++;
						}
						else
						{
							// return the quoted string, including the quotes
							return expression.substring(index, endIndex + 1);
						}
					}
					else if (c == '\\') // handle escape sequences
					{
						endIndex++; // skip the next character
						// TODO: handle octal and hex escape sequences
					}
				}
				// invalid quoted string
				throw new Error("Missing matching end quote: " + expression.substr(index));
			}
			
			// handle numbers
			var foundNumber:Object = numberRegex.exec(expression.substr(index))
			if (foundNumber)
				return foundNumber[0];

			// handle operators (find the longest matching operator)
			// this function assumes operators has already been initialized
			endIndex = index;
			var op:String = null;
			while (endIndex < n && op != '[') // special case for '[' so '[]' doesn't get treated as a single operator
			{
				op = expression.substring(index, endIndex + 1);
				if (operators[op] == undefined)
					break;
				endIndex++;
			}
			if (index < endIndex)
				return expression.substring(index, endIndex);
			
			// handle whitespace (find the longest matching sequence)
			endIndex = index;
			while (endIndex < n && WHITESPACE.indexOf(expression.charAt(endIndex)) >= 0)
				endIndex++;
			if (index < endIndex)
				return expression.substring(index, endIndex);

			// handle everything else (go until a special character is found)
			for (endIndex = index + 1; endIndex < n; endIndex++)
			{
				c = expression.charAt(endIndex);
				// whitespace terminates a token
				if (WHITESPACE.indexOf(c) >= 0)
					break;
				// operator terminates a token
				if (operators[c] != undefined)
				{
					// special case: "operator" followed by an operator symbol is treated as a single token
					if (expression.substring(index, endIndex) == OPERATOR_PREFIX)
					{
						for (var operatorLength:int = MAX_OPERATOR_LENGTH; operatorLength > 0; operatorLength--)
						{
							if (constants[expression.substring(index, endIndex + operatorLength)] is Function)
							{
								endIndex += operatorLength;
								break;
							}
						}
					}
					break;
				}
			}
			return expression.substring(index, endIndex);
		}

		/**
		 * This function will recursively compile a set of tokens into a compiled object representing a function that takes no parameters and returns a value.
		 * Example set of input tokens:  pow ( - ( - 2 + 1 ) ** - 4 , 3 ) - ( 4 + - 1 )
		 * @param tokens An Array of tokens for an expression.  This array will be modified in place.
		 * @return A CompiledConstant or CompiledFunctionCall generated from the tokens, or null if the tokens do not represent a valid expression.
		 */
		private static function compileTokens(tokens:Array):ICompiledObject
		{
			var i:int;
			var subArray:Array;
			var compiledParams:Array;
			var open:int;
			var close:int;
			
			// first step: compile quoted Strings and Numbers
			for (i = 0; i < tokens.length; i++)
			{
				var str:String = tokens[i] as String;
				if (!str)
					continue;
				
				// if the token starts with a quote, treat it as a String
				if (str.charAt(0) == '"' || str.charAt(0) == "'")
				{
					tokens[i] = compileStringLiteral(str);
				}
				else
				{
					// attempt to evaluate the token as a Number
					try {
						var number:Number = Number(str);
						if (!isNaN(number))
							tokens[i] = new CompiledConstant(str, number);
					} catch (e:Error) { }
				}
			}
			
			// next step: handle operators ".[]{}()"
			compileBracketsAndProperties(tokens);

			// -------------------

			// there are no more parentheses, so the remaining tokens are operators, constants, and variable names.
			if (debug)
				trace("compiling tokens", tokens.join(' '));
			
			// next step: handle infix '.'
			// TODO
			
			// next step: compile constants and variable names
			for (i = 0; i < tokens.length; i++)
			{
				var token:String = tokens[i] as String;
				// skip tokens that have already been compiled and skip operator tokens
				if (token == null || operators[token] != undefined)
					continue;
				// evaluate constants
				if (constants[token] != undefined)
				{
					tokens[i] = new CompiledConstant(token, constants[token]);
					continue;
				}
				// treat everything else as a variable name.
				// make a copy of the variable name that is safe for the wrapper function to use
				// compile the token as a call to variableGetter.
				tokens[i] = compileVariable(token);
			}
			
			// next step: compile unary '#' operators
			compileUnaryOperators(tokens, ['#']);
			
			// next step: compile infix '**' operators
			compileInfixOperators(tokens, ['**']);
			
			// next step: compile unary operators
			compileUnaryOperators(tokens, unaryOperatorSymbols);
			
			// next step: compile remaining infix operators in order
			for (i = 0; i < orderedOperators.length; i++)
				compileInfixOperators(tokens, orderedOperators[i]);
			
			// next step: compile conditional branches
			while (true)
			{
				// true branch includes everything between the last '?' and the next ':'
				var left:int = tokens.lastIndexOf('?');
				var right:int = tokens.indexOf(':', left);
				
				// stop if operator missing or any section has no tokens
				if (right < 0 || left < 1 || left + 1 == right || right + 1 == tokens.length)
					break;
				
				if (debug)
					trace("compiling conditional branch:", tokens.slice(left - 1, right + 2).join(' '));
				var condition:ICompiledObject = compileTokens(tokens.slice(left - 1, left));
				var trueBranch:ICompiledObject = compileTokens(tokens.slice(left + 1, right));
				var falseBranch:ICompiledObject = compileTokens(tokens.slice(right + 1, right + 2));
				
				// optimization: eliminate unnecessary branch
				var result:ICompiledObject;
				if (enableOptimizations && condition is CompiledConstant)
					result = (condition as CompiledConstant).value ? trueBranch : falseBranch;
				else
					result = compileFunctionCall(new CompiledConstant(OPERATOR_PREFIX + '?:', operators['?:']), [condition, trueBranch, falseBranch]);
				
				tokens.splice(left - 1, right - left + 3, result);
			}
			// stop if any branch operators remain
			if (Math.max(tokens.indexOf('?'), tokens.indexOf(':')) >= 0)
				throw new Error('Invalid conditional branch');
			
			// next step: variable assignment, right to left
			while (true)
			{
				for (i = tokens.length - 1; i >= 0; i--)
					if (assignmentOperators.hasOwnProperty(tokens[i]))
						break;
				if (i < 0)
					break;
				if (i == 0 || i + 1 == tokens.length)
					throw new Error("Misplaced '" + tokens[i] + "'");
				var lhs:CompiledFunctionCall = tokens[i - 1] as CompiledFunctionCall;
				var rhs:ICompiledObject = tokens[i + 1] as ICompiledObject;
				if (!lhs || !rhs)
					throw new Error("Invalid " + (!lhs ? 'left' : 'right') + "-hand-side of '" + tokens[i] + "'");
				
				// lhs should either be a constant or a call to operator.()
				
				if (lhs.evaluatedMethod is String) // lhs is a variable lookup
				{
					tokens.splice(i - 1, 3, compileOperator(tokens[i], [lhs.compiledMethod, tokens[i + 1]]));
					continue;
				}
				
				// verify that lhs.compiledMethod.name is 'operator.'
				var lhsMethod:CompiledConstant = lhs.compiledMethod as CompiledConstant;
				if (lhsMethod && lhsMethod.name == OPERATOR_PREFIX + '.')
				{
					// switch to the assignment operator
					lhs.compiledParams.push(tokens[i + 1]);
					tokens.splice(i - 1, 3, compileOperator(tokens[i], lhs.compiledParams));
					continue;
				}
				
				throw new Error("Invalid left-hand-side of '" + tokens[i] + "'");
			}

			// next step: handle multiple commands
			if (tokens.indexOf(',') >= 0)
				return compileOperator(',', compileArray(tokens));

			// last step: verify there is only one token left
			if (tokens.length == 1)
				return tokens[0];

			if (tokens.length > 1)
			{
				var leftToken:String = tokens[0] is ICompiledObject ? decompileObject(tokens[0]) : tokens[0];
				var rightToken:String = tokens[1] is ICompiledObject ? decompileObject(tokens[1]) : tokens[1];
				throw new Error("Missing operator between " + leftToken + ' and ' + rightToken);
			}

			throw new Error("Empty expression");
		}

		/*
		Escape Sequence     Character Represented
		\b                  backspace character (ASCII 8)
		\f                  form-feed character (ASCII 12)
		\n                  line-feed character (ASCII 10)
		\r                  carriage return character (ASCII 13)
		\t                  tab character (ASCII 9)
		\"                  double quotation mark
		\'                  single quotation mark
		\\                  backslash
		\000 .. \377        a byte specified in octal
		\x00 .. \xFF        a byte specified in hexadecimal
		\u0000 .. \uFFFF    a 16-bit Unicode character specified in hexadecimal
		*/
		private static const ENCODE_LOOKUP:Object = {'\b':'b', '\f':'f', '\n':'n', '\r':'r', '\t':'t', '\\':'\\', '{':'{'};
		private static const DECODE_LOOKUP:Object = {'b':'\b', 'f':'\f', 'n':'\n', 'r':'\r', 't':'\t'};
		
		/**
		 * This function surrounds a String with quotes and escapes special characters using ActionScript string literal format.
		 * @param string A String that may contain special characters.
		 * @param useDoubleQuotes If this is true, double-quote will be used.  If false, single-quote will be used.
		 * @return The given String formatted for ActionScript.
		 */
		public static function encodeString(string:String, doubleQuote:Boolean = true):String
		{
			var quote:String = doubleQuote ? '"' : "'";
			var result:Array = new Array(string.length);
			for (var i:int = 0; i < string.length; i++)
			{
				var chr:String = string.charAt(i);
				var esc:String = chr == quote ? quote : ENCODE_LOOKUP[chr];
				result[i] = esc ? '\\' + esc : chr;
			}
			return quote + result.join("") + quote;
		}
		
		/**
		 * This function is for internal use only.  It assumes the string it receives is valid.
		 * @param encodedString A quoted String with special characters escaped using ActionScript string literal format.
		 * @return The compiled string.
		 */
		private static function compileStringLiteral(quotedString:String):ICompiledObject
		{
			// remove quotes
			var quote:String = quotedString.charAt(0);
			var input:String = quotedString.substr(1, quotedString.length - 2);
			input = input.split(quote + quote).join(quote); // handle doubled quote escape sequences
			var output:String = "";
			var searchIndex:int = 0;
			var compiledObjects:Array = [];
			while (true)
			{
				var escapeIndex:int = input.indexOf("\\", searchIndex);
				if (escapeIndex < 0)
					escapeIndex = input.length;
				var bracketIndex:int = input.indexOf("{", searchIndex);
				if (bracketIndex < 0)
					bracketIndex = input.length;
				
				if (bracketIndex == escapeIndex) // handle end of string
				{
					output += input.substring(searchIndex);
					input = encodeString(output, quote == '"'); // convert to preferred syntax
					
					var compiledString:CompiledConstant = new CompiledConstant(input, output);
					
					if (compiledObjects.length == 0)
						return compiledString;
					
					compiledObjects.unshift(compiledString);
					return compileFunctionCall(new CompiledConstant('substitute', StringUtil.substitute), compiledObjects);
				}
				else if (escapeIndex < bracketIndex) // handle '\'
				{
					// look up escaped character
					var c:String = input.charAt(escapeIndex + 1);
					
					//TODO: octal and hex escape sequences
					
					c = DECODE_LOOKUP[c] || c;
					output += input.substring(searchIndex, escapeIndex) + c;
					// skip over escape sequence
					searchIndex = escapeIndex + 2;
				}
				else if (bracketIndex < escapeIndex) // handle '{'
				{
					// handle { } brackets for inline code
					var tokens:Array = [];
					var token:String = null;
					var depth:int = 1;
					escapeIndex = bracketIndex + 1;
					while (escapeIndex < input.length)
					{
						token = getToken(input, escapeIndex);
						if (token == '{')
							depth++;
						if (token == '}')
							depth--;
						if (depth == 0)
							break;
						if (WHITESPACE.indexOf(token.charAt(0)) == -1)
							tokens.push(token);
						escapeIndex += token.length;
					}
					if (escapeIndex == input.length)
						throw new Error("Missing '}' in string literal inline code: " + input);
					
					// now bracketIndex points to '{' and escapeIndex points to matching '}'
					//replace code between brackets with an int so the resulting string can be passed to StringUtil.substitute() with compiledObject as the next parameter
					output += input.substring(searchIndex, bracketIndex) + '{' + compiledObjects.length + '}';
					searchIndex = escapeIndex + 1;
					compiledObjects.push(compileTokens(tokens));
				}
			}
			return null; // unreachable
		}
		
		/**
		 * 
		 * @param leftBracket
		 * @param rightBracket
		 * @param tokens
		 */
		private static function compileBracketsAndProperties(tokens:Array):void
		{
			var token:Object;
			var compiledToken:ICompiledObject;
			var compiledParams:Array;
			var open:int;
			var close:int;
			while (true)
			{
				// find first closing bracket or '.'
				for (close = 0; close < tokens.length; close++)
					if ('.])'.indexOf(tokens[close]) >= 0)
						break;
				if (close == tokens.length || close == 0)
					break; // possible error
				// work backwards to the preceeding opening bracket or stop if '.'
				for (open = close; open >= 0; open--)
					if ('.[('.indexOf(tokens[open]) >= 0)
						break;
				if (open < 0 || open + 1 == tokens.length)
					break; // possible error
				
				// unless it's an operator, compile the token to the left
				token = open > 0 ? tokens[open - 1] : null;
				compiledToken = token as ICompiledObject;
				if (open > 0 && !compiledToken && !operators.hasOwnProperty(token))
				{
					// The function token hasn't been compiled yet.
					if (constants.hasOwnProperty(token))
						compiledToken = new CompiledConstant(token as String, constants[token]);
					else
						compiledToken = compileVariable(token as String);
				}

				// handle access operator
				if (tokens[open] == '.')
				{
					var propertyToken:String = tokens[open + 1] as String;
					if (!token || !propertyToken || operators.hasOwnProperty(propertyToken))
						break; // error
					
					// the token on the right is a variable name, but we will store it as a String because it's a property lookup
					compiledParams = [compiledToken, new CompiledConstant(encodeString(propertyToken), propertyToken)];
					tokens.splice(open - 1, 3, compileOperator('.', compiledParams));
					continue;
				}

				// cut out tokens between brackets
				var subArray:Array = tokens.splice(open + 1, close - open - 1);
				if (debug)
					trace("compiling tokens (", subArray.join(' '), ")");
				compiledParams = compileArray(subArray);

				if (tokens[open] == '[') // this is either an array or a property access
				{
					if (compiledToken)
					{
						// property access
						if (compiledParams.length == 0)
							throw new Error("Missing parameter for bracket operator: '[]'");
						// the token on the left becomes the first parameter of the access operator
						compiledParams.unshift(compiledToken);
						// replace the token to the left and the brackets with the operator call
						tokens.splice(open - 1, 3, compileOperator('.', compiledParams));
					}
					else
					{
						// array initialization -- replace '[' and ']' tokens
						tokens.splice(open, 2, compileOperator('[]', compiledParams));
					}
					continue;
				}
				
				if (tokens[open] == '{')
				{
					// TODO
					throw new Error("Unsupported bracket operator: '{'");
				}
				
				if (tokens[open] == '(')
				{
					if (compiledToken) // if there is a compiled token to the left, this is a function call
					{
						if (debug)
							trace("compiling function call", decompileObject(compiledToken));
						
						// the token to the left is the method
						// replace the function token, '(', and ')' tokens with a compiled function call
						tokens.splice(open - 1, 3, compileFunctionCall(compiledToken, compiledParams));
						continue;
					}
					else // These parentheses do not correspond to a function call.
					{
						if (compiledParams.length == 0)
							throw new Error("Missing expression inside '()'");
						
						if (compiledParams.length == 1) // single command
							tokens.splice(open, 2, compiledParams[0]);
						else // multiple commands
							tokens.splice(open, 2, compileOperator(',', compiledParams));
						continue;
					}
				}
				
				break;
			}
			for each (token in tokens)
				if (token is String && '.[](){}'.indexOf(token as String) >= 0)
					new Error("Misplaced '" + token + "'");
		}
		
		/**
		 * This function will compile a list of expressions separated by ',' tokens.
		 * @param tokens
		 * @return 
		 */
		private static function compileArray(tokens:Array):Array
		{
			// avoid compiling an empty set of tokens
			if (tokens.length == 0)
				return [];
			
			var compiledObjects:Array = [];
			while (true)
			{
				var comma:int = tokens.indexOf(',');
				if (comma >= 0)
				{
					// compile the tokens before the comma as a parameter
					compiledObjects.push(compileTokens(tokens.splice(0, comma)));
					tokens.shift(); // remove comma
				}
				else
				{
					// compile remaining group of tokens as a parameter
					compiledObjects.push(compileTokens(tokens));
					break;
				}
			}
			return compiledObjects;
		}

		/**
		 * This function is for internal use only.
		 * This function ensures that mathFunction and evaluatedParams are new Flash variables for each wrapper function created.
		 * This returns a Function with the signature:  function():*
		 * @param compiledMethod A compiled object that evaluates to a Function.
		 * @param compiledParams An array of compiled parameters that will be evaluated when the wrapper function is called.
		 * @return A CompiledObject that contains either a constant or a wrapper function that runs the functionToCompile after evaluating the compiledParams.
		 */
		private static function compileFunctionCall(compiledMethod:ICompiledObject, compiledParams:Array):ICompiledObject
		{
			var compiledFunctionCall:CompiledFunctionCall = new CompiledFunctionCall(compiledMethod, compiledParams);
			// If the compiled function call should not be evaluated to a constant, return it now.
			// Only non-assignment operators will be evaluated to constants, except for the array operator [] which creates a mutable Array.
			var constantMethod:CompiledConstant = compiledMethod as CompiledConstant;
			if (!enableOptimizations
				|| !constantMethod
				|| operators[constantMethod.name] == undefined
				|| constantMethod.name == OPERATOR_PREFIX + '[]'
				|| assignmentOperators[constantMethod.value] != undefined)
			{
				return compiledFunctionCall;
			}
			// check for CompiledFunctionCall objects in the compiled parameters
			for each (var param:ICompiledObject in compiledParams)
				if (!(param is CompiledConstant))
					return compiledFunctionCall; // this compiled funciton call cannot be evaluated to a constant
			// if there are no CompiledFunctionCall objects in the compiled parameters, evaluate the compiled function call to a constant.
			var callWrapper:Function = compileObjectToFunction(compiledFunctionCall, null); // no symbol table required for evaluating a constant
			return new CompiledConstant(decompileObject(compiledFunctionCall), callWrapper());
		}

		/**
		 * This function is for internal use only.
		 * This function is necessary because variableName needs to be a new Flash variable each time a wrapper function is created.
		 * @param variableName The name of the variable to get when the resulting wrapper function is evaluated.
		 * @param A CompiledFunctionCall for getting the variable.
		 */
		private static function compileVariable(variableName:String):CompiledFunctionCall
		{
			return new CompiledFunctionCall(new CompiledConstant(variableName, variableName), null); // params are null as a special case
		}
		
		/**
		 * This function is for internal use only.
		 * This will compile unary operators of the given type from right to left.
		 * @param compiledTokens An Array of compiled tokens for an expression.  No '(' ')' or ',' tokens should appear in this Array.
		 * @param operatorSymbols An Array containing all the infix operator symbols to compile.
		 */
		private static function compileUnaryOperators(compiledTokens:Array, operatorSymbols:Array):void
		{
			var index:int;
			for (index = compiledTokens.length - 1; index >= 0; index--)
			{
				// skip tokens that are not unary operators
				if (operatorSymbols.indexOf(compiledTokens[index]) < 0)
					continue;
				
				// fail when next token is not a compiled object
				if (index + 1 == compiledTokens.length || compiledTokens[index + 1] is String)
					throw new Error("Misplaced unary operator '" + compiledTokens[index] + "'");
				
				// skip infix operator
				if (index > 0 && compiledTokens[index - 1] is ICompiledObject)
					continue;
				
				// compile unary operator
				if (debug)
					trace("compile unary operator", compiledTokens.slice(index, index + 2).join(' '));
				compiledTokens.splice(index, 2, compileOperator(compiledTokens[index], [compiledTokens[index + 1]]));
			}
		}
		
		/**
		 * This function is for internal use only.
		 * This will compile infix operators of the given type from left to right.
		 * @param compiledTokens An Array of compiled tokens for an expression.  No '(' ')' or ',' tokens should appear in this Array.
		 * @param operatorSymbols An Array containing all the infix operator symbols to compile.
		 */
		private static function compileInfixOperators(compiledTokens:Array, operatorSymbols:Array):void
		{
			var index:int = 0;
			while (index < compiledTokens.length)
			{
				// skip tokens that are not infix operators
				if (operatorSymbols.indexOf(compiledTokens[index]) < 0)
				{
					index++;
					continue;
				}
				
				// special case code for infix operators ('**') that are evaluated prior to unary operators
				var right:int = index + 1;
				// find the next ICompiledObject
				while (right < compiledTokens.length && compiledTokens[right] is String)
					right++;
				// if there were String tokens, we need to compile unary operators on the right-hand-side
				if (right > index + 1)
				{
					// extract the right-hand-side, compile unary operators, and then insert the result to the right of the infix operator
					var rhs:Array = compiledTokens.splice(index + 1, right - index);
					compileUnaryOperators(rhs, unaryOperatorSymbols);
					if (rhs.length != 1)
						throw new Error("Unable to parse second parameter of infix operator '" + compiledTokens[index] + "'");
					compiledTokens.splice(index + 1, 0, rhs[0]);
				}
				
				// stop if infix operator does not have compiled objects on either side
				if (index == 0 || index + 1 == compiledTokens.length || compiledTokens[index - 1] is String || compiledTokens[index + 1] is String)
					throw new Error("Misplaced infix operator '" + compiledTokens[index] + "'");
				
				// replace the tokens for this infix operator call with the compiled operator call
				if (debug)
					trace("compile infix operator", compiledTokens.slice(index - 1, index + 2).join(' '));
				compiledTokens.splice(index - 1, 3, compileOperator(compiledTokens[index], [compiledTokens[index - 1], compiledTokens[index + 1]]));
			}
		}
		
		/**
		 * 
		 * @param operatorName
		 * @param compiledParams
		 * @return 
		 * 
		 */
		private static function compileOperator(operatorName:String, compiledParams:Array):ICompiledObject
		{
			// special case for variable lookup
			if (operatorName == '#')
				return new CompiledFunctionCall(compiledParams[0], null);
			operatorName = OPERATOR_PREFIX + operatorName;
			return compileFunctionCall(new CompiledConstant(operatorName, constants[operatorName]), compiledParams);
		}

		/**
		 * @param compiledObject A CompiledFunctionCall or CompiledConstant to decompile into an expression String.
		 * @return The expression String generated from the compiledObject.
		 */
		public static function decompileObject(compiledObject:ICompiledObject):String
		{
			if (compiledObject is CompiledConstant)
				return (compiledObject as CompiledConstant).name;
			
			if (debug)
				trace("decompiling: " + ObjectUtil.toString(compiledObject));
			
			var call:CompiledFunctionCall = compiledObject as CompiledFunctionCall;

			// decompile the function name
			var name:String = decompileObject(call.compiledMethod);
			var constant:CompiledConstant;
			
			// special case for variable lookup
			if (call.compiledParams == null)
			{
				constant = call.compiledMethod as CompiledConstant;
				if (constant && constant.name === constant.value)
					return name;
				return "(#" + name + ")";
			}
			
			// decompile each paramter
			var i:int;
			var params:Array = [];
			for (i = 0; i < call.compiledParams.length; i++)
				params[i] = decompileObject(call.compiledParams[i]);
			
			// replace infix operator function calls with the preferred infix syntax
			if (name.indexOf(OPERATOR_PREFIX) == 0)
			{
				var op:String = name.substr(OPERATOR_PREFIX.length);
				if (op == '.' && params.length >= 2)
				{
					var result:String = params[0];
					for (i = 1; i < params.length; i++)
					{
						// if the evaluated param compiles as a variable, use the '.' syntax
						constant = call.compiledParams[i] as CompiledConstant;
						var variable:CompiledFunctionCall = null;
						try {
							variable = compileToObject(constant.value) as CompiledFunctionCall;
							if (variable.evaluatedMethod != constant.value)
								variable = null;
						} catch (e:Error) { }
						
						if (variable)
							result += '.' + variable.evaluatedMethod;
						else
							result += '[' + params[i] + ']';
					}
					return result;
				}
				if (op == '[]')
					return '[' + params.join(', ') + ']'
				if (call.compiledParams.length == 1)
					return op + params[0];
				if (call.compiledParams.length == 2)
					return StringUtil.substitute("({0} {1} {2})", params[0], op, params[1]);
				if (call.compiledParams.length == 3 && op == '?:')
					return StringUtil.substitute("({0} ? {1} : {2})", params);
				
				if (op == ',')
					name = ''; // clear name and use the parentheses code below
			}

			return name + '(' + params.join(', ') + ')';
		}
		
		/**
		 * This function is for internal use only.
		 * @param compiledObject Either a CompiledConstant or a CompiledFunctionCall.
		 * @param symbolTable This is either a function that returns a variable by name or a lookup table containing custom variables and functions that can be used in the expression.  These values may be changed after compiling.
		 * @return A Function that takes no parameters and returns the result of evaluating the ICompiledObject.
		 */
		public static function compileObjectToFunction(compiledObject:ICompiledObject, symbolTable:Object):Function
		{
			if (compiledObject == null)
				return null;
			
			if (symbolTable == null)
				symbolTable = {};
			
			if (compiledObject is CompiledConstant)
			{
				// create a new variable for the value to avoid the overhead of
				// accessing a member variable of the CompiledConstant object.
				const value:* = (compiledObject as CompiledConstant).value;
				return function():* { return value; };
			}
			
			// create the variables that will be used inside the wrapper function
			const METHOD_INDEX:int = -1;
			const CONDITION_INDEX:int = 0;
			const TRUE_INDEX:int = 1;
			const FALSE_INDEX:int = 2;
			const BRANCH_LOOKUP:Dictionary = new Dictionary();
			BRANCH_LOOKUP[constants[OPERATOR_PREFIX + '?:']] = true;
			BRANCH_LOOKUP[constants[OPERATOR_PREFIX + '&&']] = true;
			BRANCH_LOOKUP[constants[OPERATOR_PREFIX + '||']] = false;
			const ASSIGN_OP_LOOKUP:Object = new Dictionary();
			for each (var assigOp:Function in assignmentOperators)
				ASSIGN_OP_LOOKUP[assigOp] = true;

			const stack:Array = []; // used as a queue of function calls
			var call:CompiledFunctionCall;
			var subCall:CompiledFunctionCall;
			var compiledParams:Array;
			var result:*;
			var defaultSymbolTable:Object = {};

			// return the wrapper function
			// this function avoids unnecessary function calls by keeping its own call stack rather than using recursion.
			return function(...args):*
			{
				defaultSymbolTable['this'] = this;
				defaultSymbolTable['arguments'] = args;
				// initialize top-level function and push it onto the stack
				call = compiledObject as CompiledFunctionCall;
				call.evalIndex = METHOD_INDEX;
				stack.length = 1;
				stack[0] = call;
				while (true)
				{
					// evaluate the CompiledFunctionCall on top of the stack
					call = stack[stack.length - 1] as CompiledFunctionCall;
					compiledParams = call.compiledParams;
					if (compiledParams)
					{
						// check which parameters should be evaluated
						for (; call.evalIndex < compiledParams.length; call.evalIndex++)
						{
							//trace(StringLib.lpad('', stack.length, '\t') + "[" + call.evalIndex + "] " + compiledParams[call.evalIndex].name);
							
							// handle branching and short-circuiting
							result = BRANCH_LOOKUP[call.evaluatedMethod];
							if (result !== undefined && call.evalIndex > CONDITION_INDEX)
								if (result == (call.evalIndex != (call.evaluatedParams[CONDITION_INDEX] ? TRUE_INDEX : FALSE_INDEX)))
									continue;
							
							if (call.evalIndex == METHOD_INDEX)
								subCall = call.compiledMethod as CompiledFunctionCall;
							else
								subCall = compiledParams[call.evalIndex] as CompiledFunctionCall;
							
							if (subCall != null)
							{
								// initialize subCall and push onto stack
								subCall.evalIndex = METHOD_INDEX;
								stack.push(subCall);
								break;
							}
						}
						// if more parameters need to be evaluated, evaluate the new top of the stack
						if (call.evalIndex < compiledParams.length)
							continue;
					}
					// no parameters need to be evaluated, so make the function call now
					try
					{
						if (compiledParams)
						{
							// special case for assignment operators
							if (ASSIGN_OP_LOOKUP[call.evaluatedMethod] && compiledParams.length == 2)
							{
								result = (call.evaluatedMethod as Function).call(null, defaultSymbolTable, call.evaluatedParams[0], call.evaluatedParams[1]);
							}
							else
							{
								// function call
								result = call.evaluatedMethod.apply(null, call.evaluatedParams);
							}
						}
						else
						{
							// variable lookup -- call.compiledMethod is a constant and call.evaluatedMethod is the method name
							if (symbolTable is Function)
								result = symbolTable(call.evaluatedMethod);
							else if (symbolTable.hasOwnProperty(call.evaluatedMethod))
								result = symbolTable(call.evaluatedMethod);
							if (result == undefined)
							{
								if (constants.hasOwnProperty(call.evaluatedMethod))
									result = constants[call.evaluatedMethod];
								else
									result = defaultSymbolTable[call.evaluatedMethod];
							}
						}
					}
					catch (e:Error)
					{
						if (debug)
						{
							/*
							if (compiledParams && call.evaluatedMethod == null)
							{
								while (call.compiledMethod is CompiledFunctionCall && call.evaluatedMethod == null)
									call = call.compiledMethod as CompiledFunctionCall;
								throw new Error("Undefined method: " + call.evaluatedMethod || (call.compiledMethod as CompiledConstant).value);
							}
							*/
							throw e;
						}
						result = undefined;
					}
					// remove this call from the stack
					stack.pop();
					// if there is no parent function call, return the result
					if (stack.length == 0)
						return result;
					// otherwise, store the result in the evaluatedParams array of the parent call
					call = stack[stack.length - 1] as CompiledFunctionCall;
					if (call.evalIndex == METHOD_INDEX)
						call.evaluatedMethod = result;
					else
						call.evaluatedParams[call.evalIndex] = result;
					// advance the evalIndex so the next parameter will be evaluated.
					call.evalIndex++;
				}
				return null; // unreachable
			};
		}
		
		//-----------------------------------------------------------------
		private static function test():void
		{
			var eqs:Array = [
				"1 + '\"abc ' + \"'x\\\"y\\\\\\'z\"",
				'0 ? trace("?: BUG") : -var',
				'1 ? ~-~-var : trace("?: BUG")',
				'!true && trace("&& BUG")',
				'true || trace("|| BUG")',
				'round(.5 - random() < 0 ? "1.6" : "1.4")',
				'(- x * 3) / get("var") + -2 + pow(5,3) +operator**(6,3)',
				'operator+ ( - ( - 2 + 1 ) ** - 4 , - 3 ) - ( - 4 + - 1 * - 7 )',
				'-var---3+var2',
				'(x + var) / operator+ ( - ( 2 + 1 ) ** 4 , 3 ) - ( 4 + 1 )',
				'3',
				'-3',
				'var',
				'-var',
				'roundSignificant(random(),3)',
				'rpad("hello", 4+(var+2)*2, "._,")',
				'lpad("hello", 4+(var+2)*2, "._,")',
				'substr("hello world", var*2, 5)',
				'strlen(random())',
				'concat("(0x", upper(toBase(0xFF00FF,16)), ") ", lpad(toBase(var*20, 2, 4), 9), ", base10: ", rpad(toBase(sign(var) * (var+10),10,3), 6), ", base16: ", toBase(var+10,16))'
			];
			var values:Array = [-2, -1, -0.5, 0, 0.5, 1, 2];
			var vars:Object = {};
			vars['var'] = 123;
			vars['var2'] = 222;
			vars['x'] = 10;
			vars['get'] = function(name:String):*
			{
				//trace("get variable", name, "=", vars[name]);
				return vars[name];
			};
			
			var prevDebug:Boolean = debug;
			debug = true;
			
			for each (var eq:String in eqs)
			{
				trace("expression: "+eq);
				
				var tokens:Array = getTokens(eq);
				trace("    tokens:", tokens.join(' '));
				var decompiled:String = decompileObject(compileTokens(tokens));
				trace("decompiled:", decompiled);
				
				var tokens2:Array = getTokens(decompiled);
				trace("   tokens2:", tokens2.join(' '));
				var recompiled:String = decompileObject(compileTokens(tokens2));
				trace("recompiled:", recompiled);

				enableOptimizations = true;
				var tokens3:Array = getTokens(recompiled);
				var optimized:String = decompileObject(compileTokens(tokens3));
				trace(" optimized:", optimized);
				enableOptimizations = false;
				
				var f:Function = compileToFunction(eq, vars);
				for each (var value:* in values)
				{
					vars['var'] = value;
					trace("f(var="+value+")\t= " + f(value));
				}
			}
			
			debug = prevDebug;
		}
	}
}
