// SPDX-License-Identifier: Apache-2.0
// Benchmark-only native APIs. Contract gaps are measured, not silently repaired.
use std::{
    env, fs,
    io::{self, Read, Write},
    time::Instant,
};
const MOD: u64 = 2_147_483_647;
#[derive(Default)]
struct Stats {
    rows: u64,
    bytes: u64,
    checksum: u64,
}
fn mix(a: u64, b: u64) -> u64 {
    (a * 257 + b + 1) % MOD
}
fn hex(b: &[u8]) -> String {
    if b.is_empty() {
        return "-".into();
    }
    b.iter().map(|x| format!("{x:02x}")).collect()
}
fn observe<'a, I: IntoIterator<Item = &'a [u8]>>(fields: I, n: usize, dump: bool, s: &mut Stats) {
    let mut value = n as u64;
    if dump {
        print!("R {n}");
    }
    for f in fields {
        if dump {
            print!(" {}", hex(f))
        }
        value = mix(value, f.len() as u64);
        if !f.is_empty() {
            for i in [0, f.len() / 2, f.len() - 1] {
                value = mix(value, f[i] as u64)
            }
        }
    }
    if dump {
        println!()
    }
    s.rows += 1;
    s.checksum = (s.checksum + value) % MOD;
}
fn wire_signature(b: &[u8]) -> u64 {
    let mut s = b.len() as u64;
    if !b.is_empty() {
        for i in [0, b.len() / 2, b.len() - 1] {
            s = mix(s, b[i] as u64)
        }
    }
    s
}
struct Repeated<'a> {
    data: &'a [u8],
    at: usize,
    round: usize,
    repeats: usize,
    chunk: usize,
    total: u64,
}
impl Read for Repeated<'_> {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if self.round == self.repeats || self.data.is_empty() || out.is_empty() {
            return Ok(0);
        }
        let n = out
            .len()
            .min(self.chunk - self.at % self.chunk)
            .min(self.data.len() - self.at);
        out[..n].copy_from_slice(&self.data[self.at..self.at + n]);
        self.at += n;
        self.total += n as u64;
        if self.at == self.data.len() {
            self.at = 0;
            self.round += 1
        }
        Ok(n)
    }
}
fn parse(
    engine: &str,
    data: &[u8],
    chunk: usize,
    repeats: usize,
    dump: bool,
) -> (Stats, bool, u128) {
    let source = Repeated {
        data,
        at: 0,
        round: 0,
        repeats,
        chunk,
        total: 0,
    };
    let mut s = Stats::default();
    let mut ok = true;
    match engine {
        "rust-csv" => {
            let mut r = csv::ReaderBuilder::new()
                .has_headers(false)
                .flexible(true)
                .buffer_capacity(65536)
                .from_reader(source);
            let mut row = csv::ByteRecord::new();
            let start = Instant::now();
            loop {
                match r.read_byte_record(&mut row) {
                    Ok(true) => observe(row.iter(), row.len(), dump, &mut s),
                    Ok(false) => break,
                    Err(e) => {
                        if dump {
                            println!("E native {}", hex(e.to_string().as_bytes()))
                        }
                        ok = false;
                        break;
                    }
                }
            }
            let elapsed = start.elapsed().as_nanos();
            s.bytes = r.into_inner().total;
            (s, ok, elapsed)
        }
        "simd-csv" => {
            let mut r = simd_csv::ReaderBuilder::new()
                .has_headers(false)
                .flexible(true)
                .buffer_capacity(65536)
                .from_reader(source);
            let mut row = simd_csv::ByteRecord::new();
            let start = Instant::now();
            loop {
                match r.read_byte_record(&mut row) {
                    Ok(true) => observe(row.iter(), row.len(), dump, &mut s),
                    Ok(false) => break,
                    Err(e) => {
                        if dump {
                            println!("E native {}", hex(e.to_string().as_bytes()))
                        }
                        ok = false;
                        break;
                    }
                }
            }
            let elapsed = start.elapsed().as_nanos();
            s.bytes = r.into_inner().total;
            (s, ok, elapsed)
        }
        "csv-core" => {
            let mut r = csv_core::ReaderBuilder::new().build();
            let mut bytes = vec![0u8; 4096];
            let mut ends = vec![0usize; 32];
            let (mut out, mut count, mut at, mut round) = (0, 0, 0, 0);
            let start = Instant::now();
            loop {
                let input = if round < repeats && !data.is_empty() {
                    &data[at..data.len().min((at / chunk + 1) * chunk)]
                } else {
                    &[]
                };
                let (res, ni, no, ne) = r.read_record(input, &mut bytes[out..], &mut ends[count..]);
                at += ni;
                s.bytes += ni as u64;
                out += no;
                count += ne;
                if at == data.len() && round < repeats && !data.is_empty() {
                    at = 0;
                    round += 1
                }
                match res {
                    csv_core::ReadRecordResult::Record => {
                        let mut begin = 0;
                        let fields = ends[..count].iter().map(|&end| {
                            let f = &bytes[begin..end];
                            begin = end;
                            f
                        });
                        observe(fields, count, dump, &mut s);
                        out = 0;
                        count = 0
                    }
                    csv_core::ReadRecordResult::End => break,
                    csv_core::ReadRecordResult::OutputFull => bytes.resize(bytes.len() * 2, 0),
                    csv_core::ReadRecordResult::OutputEndsFull => ends.resize(ends.len() * 2, 0),
                    csv_core::ReadRecordResult::InputEmpty => {}
                }
            }
            (s, true, start.elapsed().as_nanos())
        }
        _ => panic!("unknown parser"),
    }
}
struct Sink {
    bytes: Vec<u8>,
    stats: Stats,
    dump: bool,
}
impl Write for Sink {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.bytes.extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        if !self.bytes.is_empty() {
            observe_wire(&self.bytes, self.dump, &mut self.stats);
            self.bytes.clear();
        }
        Ok(())
    }
}
fn observe_wire(b: &[u8], dump: bool, s: &mut Stats) {
    if dump {
        println!("W {}", hex(b))
    }
    s.rows += 1;
    s.bytes += b.len() as u64;
    s.checksum = (s.checksum + wire_signature(b)) % MOD;
}
fn encode(engine: &str, rows: &[Vec<Vec<u8>>], repeats: usize, dump: bool) -> (Stats, bool, u128) {
    let sink = Sink {
        bytes: Vec::with_capacity(4096),
        stats: Stats::default(),
        dump,
    };
    let mut s = Stats::default();
    match engine {
        "rust-csv" => {
            let records: Vec<csv::ByteRecord> = rows
                .iter()
                .map(|r| csv::ByteRecord::from(r.clone()))
                .collect();
            let mut w = csv::WriterBuilder::new()
                .flexible(true)
                .terminator(csv::Terminator::CRLF)
                .buffer_capacity(65536)
                .from_writer(sink);
            let start = Instant::now();
            for _ in 0..repeats {
                for row in &records {
                    w.write_byte_record(row).unwrap();
                    w.flush().unwrap();
                }
            }
            let elapsed = start.elapsed().as_nanos();
            let sink = w.into_inner().unwrap_or_else(|_| panic!("sink failed"));
            (sink.stats, true, elapsed)
        }
        "simd-csv" => {
            let records: Vec<simd_csv::ByteRecord> = rows
                .iter()
                .map(|r| simd_csv::ByteRecord::from(r.clone()))
                .collect();
            let mut w = simd_csv::WriterBuilder::new()
                .flexible(true)
                .crlf_newlines(true)
                .buffer_capacity(65536)
                .from_writer(sink);
            let start = Instant::now();
            for _ in 0..repeats {
                for row in &records {
                    w.write_byte_record(row).unwrap();
                    w.flush().unwrap();
                }
            }
            let elapsed = start.elapsed().as_nanos();
            let sink = w.into_inner().unwrap_or_else(|_| panic!("sink failed"));
            (sink.stats, true, elapsed)
        }
        "csv-core" => {
            let records: Vec<csv::ByteRecord> = rows
                .iter()
                .map(|r| csv::ByteRecord::from(r.clone()))
                .collect();
            let mut w = csv_core::WriterBuilder::new()
                .terminator(csv_core::Terminator::CRLF)
                .build();
            let mut bytes = vec![0u8; 4096];
            let start = Instant::now();
            for _ in 0..repeats {
                for row in &records {
                    let mut out = 0;
                    for (i, f) in row.iter().enumerate() {
                        if i > 0 {
                            loop {
                                let (res, n) = w.delimiter(&mut bytes[out..]);
                                out += n;
                                if res == csv_core::WriteResult::InputEmpty {
                                    break;
                                }
                                bytes.resize(bytes.len() * 2, 0)
                            }
                        }
                        let mut at = 0;
                        loop {
                            let (res, ni, no) = w.field(&f[at..], &mut bytes[out..]);
                            at += ni;
                            out += no;
                            if res == csv_core::WriteResult::InputEmpty {
                                break;
                            }
                            bytes.resize(bytes.len() * 2, 0)
                        }
                    }
                    loop {
                        let (res, n) = w.terminator(&mut bytes[out..]);
                        out += n;
                        if res == csv_core::WriteResult::InputEmpty {
                            break;
                        }
                        bytes.resize(bytes.len() * 2, 0)
                    }
                    observe_wire(&bytes[..out], dump, &mut s)
                }
            }
            (s, true, start.elapsed().as_nanos())
        }
        _ => panic!("unknown writer"),
    }
}
fn rows(data: &[u8]) -> Vec<Vec<Vec<u8>>> {
    assert!(data.len() <= 8 * 1024 * 1024 && data.starts_with(b"GCFIELDS"));
    let mut at = 8;
    fn count(b: &[u8], at: &mut usize) -> usize {
        let end = at.checked_add(4).unwrap();
        let n = u32::from_le_bytes(b.get(*at..end).unwrap().try_into().unwrap()) as usize;
        *at = end;
        n
    }
    let n = count(data, &mut at);
    assert!(n <= 65536);
    let mut rows = Vec::with_capacity(n);
    for _ in 0..n {
        let fields = count(data, &mut at);
        assert!(fields <= 65536);
        let mut row = Vec::with_capacity(fields);
        for _ in 0..fields {
            let len = count(data, &mut at);
            let end = at.checked_add(len).unwrap();
            row.push(data.get(at..end).unwrap().to_vec());
            at = end
        }
        rows.push(row)
    }
    assert_eq!(at, data.len());
    rows
}
fn main() {
    let args: Vec<String> = env::args().collect();
    assert_eq!(args.len(), 7, "engine parse|write file chunk repeats dump");
    let data = fs::read(&args[3]).unwrap();
    assert!(data.len() <= 8 * 1024 * 1024);
    let chunk: usize = args[4].parse().unwrap();
    let repeats: usize = args[5].parse().unwrap();
    assert!((1..=1000000).contains(&repeats));
    let dump = args[6] == "1";
    let (s, ok, ns) = match args[2].as_str() {
        "parse" => {
            assert!(chunk > 0);
            parse(&args[1], &data, chunk, repeats, dump)
        }
        "write" => encode(&args[1], &rows(&data), repeats, dump),
        _ => panic!("unknown mode"),
    };
    println!(
        "S {} {} {} {} {}",
        s.rows,
        s.bytes,
        s.checksum,
        ns,
        if ok { "ok" } else { "error" }
    );
}
