//! Inner doc comment.
/// Outer doc comment.
// Plain line comment.
/* Block comment
   /* nested block */
   still inside the outer block
*/
pub fn strings() -> usize {
    let url = "http://example.invalid // not a comment";
    let raw = r#"has // and /* inside a raw string"#;
    let multi = "first line
// this line is inside a string
last line";
    /* leading block */ let a = 1;
    let b = 2; /* trailing block */
    url.len() + raw.len() + multi.len() + a + b
}

pub fn chars() -> usize {
    let quote = '"';
    let x = 1;
    // a comment after a quote char
    let y = 2;
    let z = "z";
    x + y + z.len() + quote.len_utf8()
}

pub fn lifetimes<'a>(s: &'a str) -> &'a str {
    s
}
