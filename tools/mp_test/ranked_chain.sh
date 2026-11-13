#!/usr/bin/env bash
cd /opt/gamebox/repo
export MP_TEST_FLOW=${CHAIN_FLOW:-ranked} MP_TEST_SHOTS=1 MP_TEST_TIMEOUT=900 MP_TEST_RANKED_RP=1 MP_TEST_RANKED_SHOWCASE=1
for job in "$@"; do
    name=${job%%:*}
    envs=${job#*:}
    echo "== $name $(date +%T)" >> /root/chain.log
    env $envs MP_TEST_OUT=tools/mp_test/out_$name bash tools/mp_test/run.sh > /root/$name.log 2>&1
    echo "== $name done $? $(date +%T)" >> /root/chain.log
done
echo "== chain done $(date +%T)" >> /root/chain.log
