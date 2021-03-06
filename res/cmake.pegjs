// A grammar for any file written in CMake language 
//(https://cmake.org/cmake/help/latest/manual/cmake-language.7.html)

/*
needs simplification:
define return array contents
maybe everything should return an array and it is flattened at some point
*/

{
    /*
        The result array consists of objects with members:
        - type: one of ['whitespace', 'comment','command']
        - class:
            - for whitespace one of ['space','newline']
            - for comment one of ['line', 'bracket']
            - for command it is undefined
        - name: identifier of a command
        - args: for command only, flat array of all arguments (including whitespace and comments)

    */
    var elements=[]
    // bracket count for bracket arguments, to match same count in closing bracket
    var tmpBC = 0;
	
    function cWhiteSpace(cl, txt, loc){
        return {type:"whitespace", class:cl, value:txt, location:loc};
    }

    function cComment(cl, txt, loc){
        return {type:"comment", class:cl, value:txt, location:loc};
    }

    function cArg(cl, txt, loc){
        return {type:"argument", class:cl, name:txt, location:loc};
    }

    function flattenDeep(arr1){
    return arr1.reduce((acc, val) => Array.isArray(val) ? acc.concat(flattenDeep(val)) : acc.concat(val), []);
    };
}

// A CMake Language source file consists of zero or more Command Invocations 
// separated by newlines and optionally spaces and Comments.
file         =  file_element* 
                {return elements}
// CMake accepts the last line in the file without newline, so should the parser
file_element =  ci:command_invocation sp:(space*) le:line_ending?
                {
                    elements.push(ci);
                    if(sp.length != 0){
                        elements.push(sp);
                    }
                    if (le) elements=elements.concat(le);
                } 
                / bc:(bracket_comment/space)* le:line_ending
                {
                    if( bc.length > 0) {
                        elements.push(bc);
                    }
                    elements=elements.concat(le);
                }
                // lines with space only
                / s:space
                {
                    elements.push(s);
                }
                
// although a line may always be terminated with a newline, 
// CMake accepts the last line in the file without newline, so should the parser
line_ending  =  lc:line_comment nl:newline?
                {
                	if (nl){ return [lc,nl]; }
                    else { return [lc]}
                }
                / newline
// A # not immediately followed by a Bracket Argument forms a line comment that runs until the end of the line:
// also cover the empty line comment (the newline shall not be part of the comment)
line_comment =  '#'[^\[\r\n]?[^\r\n]* 
                { return cComment('line', text().slice(1), location()) }
space        =  sp:[ \t]+ 
                { return  cWhiteSpace('space', sp.join(''), location()) }
newline "newline"  =  '\n' 
               { return cWhiteSpace('newline', text(), location()) }
                / '\r\n'
               { return cWhiteSpace('newline', text(), location()) }
// Note that any source file line not inside Command Arguments or a Bracket Comment 
// can end in a Line Comment.

// A command invocation is a name followed by paren-enclosed arguments separated by whitespace.
command_invocation  = cindent:space* comm:identifier aindent:(space*) '(' args:arguments ')'
                        {
                            return { type:"command"
                                    ,cindent:cindent.join('')
                                    ,name:comm
                                    ,args: flattenDeep(args)
                                    ,aindent:aindent.join('') 
                                    ,loc:location() }
                                  } 
// returns the whole identifier as string
identifier          =  iden:( [A-Za-z_][A-Za-z0-9_]* ) {return `${iden[0]}${iden[1].join('')}`}
arguments           =  a:argument? sa:separated_arguments* 
                        {
                            // flatten array from 2 to one dimension
                            if( a != null ){
                                sa.splice(0,0,a);
                            }
                            return sa;
                        }
separated_arguments =  s:separation+ a:argument? 
                        {
                            // one array for all results
                            if( a != null ){
                                s.push(a)
                            }
                            return s;
                        }
                        / separation* '(' arguments ')'
separation          =  space / line_ending
/*
Command names are case-insensitive. Nested unquoted parentheses in the arguments must balance. 
Each ( or ) is given to the command invocation as a literal Unquoted Argument. 
This may be used in calls to the if() command to enclose conditions
*/

// There are three types of arguments within Command Invocations:
argument =  ba:bracket_argument    {return cArg('bracket', ba, location() ) } 
            / qa:quoted_argument   {return cArg('quoted', qa, location() ) } 
            / ua:unquoted_argument {return cArg('unquoted', ua, location() ) }

// A bracket argument, inspired by Lua long bracket syntax, encloses content between opening and closing “brackets” of the same length:
bracket_argument =  bracket_open c:bracket_content bracket_close { return c; }
bracket_open     =  '[' eq:('=' *) '[' 
                    { 
                        tmpBC = eq.length
                        return text()
                    }
//any text not containing a bracket_close with the same number of '=' as the bracket_open
bracket_content  = (!bracket_close .)*  { return text()}
// bracket close should match the same amount of equal signs
bracket_close    =  ']' eq:('=' *) ']' &{
						// if the number of equal signs does not macht, it is not treated as a bracket argument, but an unquoted argument
                        return eq.length == tmpBC;
                    }
/*
An opening bracket is written [ followed by zero or more = followed by [. The corresponding 
closing bracket is written ] followed by the same number of = followed by ]. Brackets do not nest. 
A unique length may always be chosen for the opening and closing brackets to contain closing 
brackets of other lengths.

Bracket argument content consists of all text between the opening and closing brackets, 
except that one newline immediately following the opening bracket, if any, is ignored. 
No evaluation of the enclosed content, such as Escape Sequences or Variable References, 
is performed. A bracket argument is always given to the command invocation as exactly one argument.
*/

// A quoted argument encloses content between opening and closing double-quote characters:
quoted_argument     =  '"' ele:( quoted_element* ) '"' { return ele.join('') }
quoted_element      =  [^\\\"] / escape_sequence / quoted_continuation
quoted_continuation =  '\\' newline
/*
Quoted argument content consists of all text between opening and closing quotes. 
Both Escape Sequences and Variable References are evaluated. A quoted argument is always 
given to the command invocation as exactly one argument.
*/

// An unquoted argument is not enclosed by any quoting syntax. 
// It may not contain any whitespace, (, ), #, ", or \ except when escaped by a backslash:
unquoted_argument =  ele: unquoted_element+ { return ele.join('').trim()}
// <any character except whitespace or one of '()#"\'>
// to support legacy CMake code, unquoted arguments may also contain double-quoted strings 
//("...", possibly enclosing horizontal whitespace), and make-style variable references ($(MAKEVAR)).
unquoted_element  =   [^\(\)#\\ \t\n\r] / escape_sequence

// An escape sequence is a \ followed by one character:
escape_sequence  =  escape_identity / escape_encoded / escape_semicolon
escape_identity  =  '\\'e:[^A-Za-z0-9;] { return e }
escape_encoded   =  '\\t' / '\\r' / '\\n'
escape_semicolon =  '\\;'

// A # immediately followed by a Bracket Argument forms a bracket comment consisting of the entire bracket enclosure:
bracket_comment =  '#' bracket_argument


