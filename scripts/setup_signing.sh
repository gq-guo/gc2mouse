#!/bin/zsh
# 在登录钥匙串里创建本机自签名的代码签名证书「gc2mouse Local Signing」。
# 用固定证书签名后，重新编译不会让「辅助功能」授权失效。
# 私钥只在权限 700 的临时目录里短暂存在，导入后立即删除。删除：钥匙串访问 → 登录 → 我的证书 → 删除该证书。
set -e
NAME="gc2mouse Local Signing"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "证书已存在：$NAME"
  exit 0
fi

# 用系统自带的 LibreSSL：它导出的 PKCS#12 格式 macOS 钥匙串能直接导入
OSSL=/usr/bin/openssl
TMP=$(mktemp -d)
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/req.conf"
cat > "$CONF" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 仅用于本次导入的一次性口令
PASS=$($OSSL rand -hex 16)
BUNDLE="$TMP/identity.bundle"
$OSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$CONF" -keyout /dev/stdout -out /dev/stdout 2>/dev/null \
  | $OSSL pkcs12 -export -name "$NAME" -passout "pass:$PASS" \
      -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 -out "$BUNDLE"
security import "$BUNDLE" -k "$KEYCHAIN" -f pkcs12 -P "$PASS" -T /usr/bin/codesign
unset PASS
echo "已创建：$NAME"
