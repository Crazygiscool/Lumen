fn main() {
    let method = std::ffi::CString::new("sys.hardware").unwrap();
    let args = std::ffi::CString::new("{}").unwrap();
    unsafe {
        let out = fscore::fscore_call(method.as_ptr(), args.as_ptr());
        let s = std::ffi::CStr::from_ptr(out).to_string_lossy().into_owned();
        fscore::fscore_free(out);
        println!("{}", &s[..400.min(s.len())]);
    }
}
