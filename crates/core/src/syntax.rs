//! Formula language 0: tokens and syntax tree.
//!
//! Grammar, loosest binding first: `or`, `and`, `not`, one comparison, `+ -`, `* /`,
//! unary `-`. See docs/spec/02-formula-language-v0.md.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinOp {
    Or,
    And,
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
    Add,
    Sub,
    Mul,
    Div,
}

impl BinOp {
    pub fn symbol(self) -> &'static str {
        match self {
            BinOp::Or => "or",
            BinOp::And => "and",
            BinOp::Lt => "<",
            BinOp::Le => "<=",
            BinOp::Gt => ">",
            BinOp::Ge => ">=",
            BinOp::Eq => "==",
            BinOp::Ne => "!=",
            BinOp::Add => "+",
            BinOp::Sub => "-",
            BinOp::Mul => "*",
            BinOp::Div => "/",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Node {
    Int(i64),
    Real(f64),
    Bool(bool),
    Name(String),
    Neg(Box<Node>),
    Not(Box<Node>),
    Bin(BinOp, Box<Node>, Box<Node>),
    Call(String, Vec<Node>),
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Int(i64),
    Real(f64),
    Name(String),
    Op(&'static str),
    End,
}

const OPERATORS: [&str; 13] = ["<=", ">=", "==", "!=", "-", "+", "*", "/", "(", ")", "<", ">", ","];

fn tokenize(src: &str) -> Result<Vec<Token>, String> {
    let text: Vec<char> = src.trim_end().chars().collect();
    let mut tokens = Vec::new();
    let mut pos = 0;
    while pos < text.len() {
        while pos < text.len() && text[pos].is_whitespace() {
            pos += 1;
        }
        let start = pos;
        let c = text[pos];
        if c.is_ascii_digit() {
            // digits and underscores, an optional fraction, an optional exponent
            let mut real = false;
            while pos < text.len() && (text[pos].is_ascii_digit() || text[pos] == '_') {
                pos += 1;
            }
            if pos + 1 < text.len() && text[pos] == '.' && text[pos + 1].is_ascii_digit() {
                real = true;
                pos += 1;
                while pos < text.len() && (text[pos].is_ascii_digit() || text[pos] == '_') {
                    pos += 1;
                }
            }
            if pos < text.len() && (text[pos] == 'e' || text[pos] == 'E') {
                let mut probe = pos + 1;
                if probe < text.len() && (text[probe] == '+' || text[probe] == '-') {
                    probe += 1;
                }
                if probe < text.len() && text[probe].is_ascii_digit() {
                    real = true;
                    while probe < text.len() && text[probe].is_ascii_digit() {
                        probe += 1;
                    }
                    pos = probe;
                }
            }
            let raw: String = text[start..pos].iter().filter(|c| **c != '_').collect();
            if real {
                tokens.push(Token::Real(raw.parse::<f64>().map_err(|_| format!("bad number {raw:?}"))?));
            } else {
                let value = raw.parse::<i64>().map_err(|_| "integer literal does not fit in 64 bits".to_string())?;
                tokens.push(Token::Int(value));
            }
        } else if c.is_ascii_alphabetic() || c == '_' {
            while pos < text.len() && (text[pos].is_ascii_alphanumeric() || text[pos] == '_') {
                pos += 1;
            }
            tokens.push(Token::Name(text[start..pos].iter().collect()));
        } else {
            let two: String = text[pos..(pos + 2).min(text.len())].iter().collect();
            let one: String = text[pos..pos + 1].iter().collect();
            if let Some(op) = OPERATORS.iter().find(|op| **op == two) {
                tokens.push(Token::Op(op));
                pos += 2;
            } else if let Some(op) = OPERATORS.iter().find(|op| **op == one) {
                tokens.push(Token::Op(op));
                pos += 1;
            } else {
                return Err(format!("unexpected character at column {}", pos + 1));
            }
        }
    }
    tokens.push(Token::End);
    Ok(tokens)
}

struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}

impl Parser {
    fn peek(&self) -> &Token {
        &self.tokens[self.pos]
    }

    fn accept_op(&mut self, ops: &[&str]) -> Option<&'static str> {
        if let Token::Op(op) = self.peek() {
            let op = *op;
            if ops.contains(&op) {
                self.pos += 1;
                return Some(op);
            }
        }
        None
    }

    fn accept_word(&mut self, word: &str) -> bool {
        if matches!(self.peek(), Token::Name(name) if name == word) {
            self.pos += 1;
            return true;
        }
        false
    }

    fn expr(&mut self) -> Result<Node, String> {
        let mut node = self.conj()?;
        while self.accept_word("or") {
            node = Node::Bin(BinOp::Or, Box::new(node), Box::new(self.conj()?));
        }
        Ok(node)
    }

    fn conj(&mut self) -> Result<Node, String> {
        let mut node = self.negation()?;
        while self.accept_word("and") {
            node = Node::Bin(BinOp::And, Box::new(node), Box::new(self.negation()?));
        }
        Ok(node)
    }

    fn negation(&mut self) -> Result<Node, String> {
        if self.accept_word("not") {
            return Ok(Node::Not(Box::new(self.negation()?)));
        }
        self.comparison()
    }

    fn comparison(&mut self) -> Result<Node, String> {
        let node = self.sum()?;
        if let Some(op) = self.accept_op(&["<", "<=", ">", ">=", "==", "!="]) {
            let op = match op {
                "<" => BinOp::Lt,
                "<=" => BinOp::Le,
                ">" => BinOp::Gt,
                ">=" => BinOp::Ge,
                "==" => BinOp::Eq,
                _ => BinOp::Ne,
            };
            return Ok(Node::Bin(op, Box::new(node), Box::new(self.sum()?)));
        }
        Ok(node)
    }

    fn sum(&mut self) -> Result<Node, String> {
        let mut node = self.product()?;
        while let Some(op) = self.accept_op(&["+", "-"]) {
            let op = if op == "+" { BinOp::Add } else { BinOp::Sub };
            node = Node::Bin(op, Box::new(node), Box::new(self.product()?));
        }
        Ok(node)
    }

    fn product(&mut self) -> Result<Node, String> {
        let mut node = self.unary()?;
        while let Some(op) = self.accept_op(&["*", "/"]) {
            let op = if op == "*" { BinOp::Mul } else { BinOp::Div };
            node = Node::Bin(op, Box::new(node), Box::new(self.unary()?));
        }
        Ok(node)
    }

    fn unary(&mut self) -> Result<Node, String> {
        if self.accept_op(&["-"]).is_some() {
            return Ok(Node::Neg(Box::new(self.unary()?)));
        }
        self.primary()
    }

    fn primary(&mut self) -> Result<Node, String> {
        let token = self.tokens[self.pos].clone();
        self.pos += 1;
        match token {
            Token::Int(v) => Ok(Node::Int(v)),
            Token::Real(v) => Ok(Node::Real(v)),
            Token::Name(name) => {
                match name.as_str() {
                    "true" => return Ok(Node::Bool(true)),
                    "false" => return Ok(Node::Bool(false)),
                    "and" | "or" | "not" => return Err(format!("unexpected keyword {name:?}")),
                    _ => {}
                }
                if self.accept_op(&["("]).is_some() {
                    let mut args = Vec::new();
                    if self.accept_op(&[")"]).is_none() {
                        loop {
                            args.push(self.expr()?);
                            if self.accept_op(&[")"]).is_some() {
                                break;
                            }
                            if self.accept_op(&[","]).is_none() {
                                return Err("expected ',' or ')' in argument list".to_string());
                            }
                        }
                    }
                    return Ok(Node::Call(name, args));
                }
                Ok(Node::Name(name))
            }
            Token::Op("(") => {
                let node = self.expr()?;
                if self.accept_op(&[")"]).is_none() {
                    return Err("expected ')'".to_string());
                }
                Ok(node)
            }
            Token::End => {
                self.pos -= 1;
                Err("formula ends unexpectedly".to_string())
            }
            Token::Op(op) => Err(format!("unexpected {op:?}")),
        }
    }
}

/// Parses one formula into a syntax tree.
pub fn parse(src: &str) -> Result<Node, String> {
    let mut parser = Parser { tokens: tokenize(src)?, pos: 0 };
    let node = parser.expr()?;
    match parser.peek() {
        Token::End => Ok(node),
        other => Err(format!("unexpected {other:?}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn precedence() {
        let n = parse("1 + 2 * 3").unwrap();
        assert_eq!(
            n,
            Node::Bin(
                BinOp::Add,
                Box::new(Node::Int(1)),
                Box::new(Node::Bin(BinOp::Mul, Box::new(Node::Int(2)), Box::new(Node::Int(3))))
            )
        );
        assert!(parse("not a or b").is_ok());
        assert!(parse("f(1, g(x), -y)").is_ok());
        assert_eq!(parse("1_000").unwrap(), Node::Int(1000));
        assert_eq!(parse("2.5E-1").unwrap(), Node::Real(0.25));
    }

    #[test]
    fn rejections() {
        for bad in ["", "1 +", "(1", "1 2", "@", "1.", "1e", "9223372036854775808", "1 < 2 < 3", "1 = 1", "and", "f(1,)"] {
            assert!(parse(bad).is_err(), "{bad:?} should not parse");
        }
    }
}
