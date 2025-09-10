use std::fmt::{self, Formatter};

use serde::{Deserialize, Serialize};

use crate::utils::deserialize_string_from_hexstring;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TypeInfo {
    pub account_address: String,
    #[serde(deserialize_with = "deserialize_string_from_hexstring")]
    pub module_name: String,
    #[serde(deserialize_with = "deserialize_string_from_hexstring")]
    pub struct_name: String,
}

impl fmt::Display for TypeInfo {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        write!(
            f,
            "{}::{}::{}",
            self.account_address, self.module_name, self.struct_name
        )
    }
}
