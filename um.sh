function setupVars {
	if [ ! $UMEE_NODENAME ]; then
		read -p "Enter node name: " UMEE_NODENAME
		echo 'export UMEE_NODENAME='\"${UMEE_NODENAME}\" >> $HOME/.bash_profile
	fi
	if [ ! $UMEE_WALLET ]; then
		read -p "Enter wallet name: " UMEE_WALLET
		echo 'export UMEE_WALLET='\"${UMEE_WALLET}\" >> $HOME/.bash_profile
	fi
	echo -e '\n\e[42mYour wallet name:' $UMEE_WALLET '\e[0m\n'
	echo 'export UMEE_CHAIN=umee-betanet-2' >> $HOME/.bash_profile
	. $HOME/.bash_profile
	sleep 1
}

function setupSwap {
	echo -e '\n\e[42mSet up swapfile\e[0m\n'
	curl -s https://api.nodes.guru/swap4.sh | bash
}

function installGo {
	echo -e '\n\e[42mInstall Go\e[0m\n' && sleep 1
	cd $HOME
	wget -O go1.17.3.linux-amd64.tar.gz https://golang.org/dl/go1.17.3.linux-amd64.tar.gz
	rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.3.linux-amd64.tar.gz && rm go1.17.3.linux-amd64.tar.gz
	echo 'export GOROOT=/usr/local/go' >> $HOME/.bash_profile
	echo 'export GOPATH=$HOME/go' >> $HOME/.bash_profile
	echo 'export GO111MODULE=on' >> $HOME/.bash_profile
	echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile && . $HOME/.bash_profile
	go version
}

function installDeps {
	echo -e '\n\e[42mPreparing to install\e[0m\n' && sleep 1
	cd $HOME
	sudo apt update
	sudo apt install make clang pkg-config libssl-dev build-essential git jq ncdu -y < "/dev/null"
	installGo
}

function installCosmovisor {
	echo -e '\n\e[42mInstall Cosmovisor\e[0m\n' && sleep 1
	cd $HOME
	go get github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor
	useradd --no-create-home --shell /bin/false cosmovisor
	mkdir $HOME/cosmovisor
	mkdir -p $HOME/cosmovisor/genesis/bin
	cp $(which umeed) $HOME/cosmovisor/genesis/bin
	cp $(which cosmovisor) $HOME/cosmovisor
	chown -R cosmovisor:cosmovisor $HOME/cosmovisor
}

function installOrchestrator {
echo -e '\n\e[42mInstall Orchestrator\e[0m\n' && sleep 1
mv $HOME/gorc $HOME/.gorc.bak
wget -O gorc https://github.com/PeggyJV/gravity-bridge/releases/download/v0.2.23/gorc
chmod +x ./gorc
mv ./gorc /usr/local/bin
mkdir $HOME/gorc && cd $HOME/gorc
cp -r $HOME/.gorc.bak/keystore $HOME/gorc
contract_address="0xc846512f680a2161D2293dB04cbd6C294c5cFfA7"
echo "keystore = \"$HOME/gorc/keystore/\"

[gravity]
contract = \"$contract_address\"
fees_denom = \"uumee\"

[ethereum]
key_derivation_path = \"m/44'/60'/0'/0/0\"
rpc = \"https://rinkeby.nodes.guru:443\"
gas_price_multiplier = 1.0

[cosmos]
key_derivation_path = \"m/44'/118'/0'/0/0\"
grpc = \"http://localhost:9090\"
prefix = \"umee\"

[cosmos.gas_price]
amount = 0.00001
denom = \"uumee\"

[metrics]
listen_addr = \"127.0.0.1:3000\"
" > $HOME/gorc/config.toml
}

function generateKeysOrchestrator {
echo -e "[Orchestrator] Set up your \e[7mcosmos\e[0m wallet"
gorc --config $HOME/gorc/config.toml keys cosmos add "$UMEE_WALLET"_cosmos > $HOME/umee_"$UMEE_WALLET"_cosmos_key.txt
echo -e "[Orchestrator] You can get your mnemonic via \e[7mcat $HOME/umee_"$UMEE_WALLET"_cosmos_key.txt\e[0m"
cat $HOME/umee_"$UMEE_WALLET"_cosmos_key.txt | head -n 1
echo -e "[Orchestrator] Set up your \e[7meth\e[0m wallet"
gorc --config $HOME/gorc/config.toml keys eth add "$UMEE_WALLET"_eth > $HOME/umee_"$UMEE_WALLET"_eth_key.txt
echo -e "[Orchestrator] You can get your mnemonic via \e[7mcat $HOME/umee_"$UMEE_WALLET"_eth_key.txt\e[0m"
cat $HOME/umee_"$UMEE_WALLET"_eth_key.txt | head -n 1
eth_addr=`cat $HOME/umee_"$UMEE_WALLET"_eth_key.txt | tail -1`
echo -e "[Orchestrator] You should send some Rinkeby ETH to the wallet address: \e[7m$eth_addr\e[0m"
echo -e "[Orchestrator] You can do it via: \e[7mhttps://faucet.rinkeby.io/\e[0m"
}

function createServiceOrchestrator {
echo "[Unit]
Description=Gravity Bridge Orchestrator
After=online.target

[Service]
#Type=root
User=$USER
Environment=\"RUST_LOG=INFO\"
ExecStart=/usr/local/bin/gorc --config $HOME/gorc/config.toml orchestrator start --cosmos-key "$UMEE_WALLET"_cosmos --ethereum-key "$UMEE_WALLET"_eth
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/gorc.service
systemctl daemon-reload
systemctl enable gorc
systemctl restart gorc
}

function installGeth {
echo -e '\n\e[42mInstall Ethereum Node (light)\e[0m\n' && sleep 1
cd $HOME
wget -O $HOME/geth.tar.gz https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.12-6c4dc6c3.tar.gz
tar -xzf geth.tar.gz
cp $HOME/geth-linux-amd64-1.10.12-6c4dc6c3/geth /usr/bin
rm geth.tar.gz
}

function createServiceGeth {
cd $HOME
wget https://www.rinkeby.io/rinkeby.json
geth init rinkeby.json
#ExecStart=/usr/bin/geth --syncmode \"light\" --goerli --rpc --rpcport \"8545\"
#ExecStart=/usr/bin/geth --syncmode \"light\"  --http --http.addr=0.0.0.0 --http.port=8545 --cache=16 --ethash.cachesinmem=1 --rinkeby --v5disc --bootnodes=enode://a24ac7c5484ef4ed0c5eb2d36620ba4e4aa13b8c84684e1b4aab0cebea2ae45cb4d375b77eab56516d34bfbd3c1a833fc51296ff084b770b94fb9028c4d25ccf@52.169.42.101:30303
#ExecStart=/usr/bin/geth --syncmode \"light\"  --http --http.addr=0.0.0.0 --http.port=8545 --cache=16 --ethash.cachesinmem=1 --rinkeby --v5disc --bootnodes=enode://343149e4feefa15d882d9fe4ac7d88f885bd05ebb735e547f12e12080a9fa07c8014ca6fd7f373123488102fe5e34111f8509cf0b7de3f5b44339c9f25e87cb8@52.3.158.184:30303
echo "[Unit]
Description=Geth node
After=online.target

[Service]
#Type=root
User=$USER
ExecStart=/usr/bin/geth --syncmode \"light\" --http --http.addr=0.0.0.0 --http.port=8545 --rinkeby --bootnodes=enode://a24ac7c5484ef4ed0c5eb2d36620ba4e4aa13b8c84684e1b4aab0cebea2ae45cb4d375b77eab56516d34bfbd3c1a833fc51296ff084b770b94fb9028c4d25ccf@52.169.42.101:30303
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/geth.service
systemctl daemon-reload
systemctl enable geth
systemctl restart geth
}

function installSoftware {
	echo -e '\n\e[42mInstall software\e[0m\n' && sleep 1
	mkdir -p $HOME/data
	cd $HOME
	git clone --depth 1 --branch v0.3.0 https://github.com/umee-network/umee.git
	cd umee && make install
	umeed version
	umeed init ${UMEE_NODENAME} --chain-id $UMEE_CHAIN
	wget -O $HOME/.umee/config/genesis.json "https://github.com/umee-network/testnets/blob/main/networks/umeevengers-1c/genesis.json"
	# sed -i.bak -e "s/^minimum-gas-prices = \"\"/minimum-gas-prices = \"0.001uumee\"/; s/^pruning = \"default\"/pruning = \"nothing\"/" $HOME/.umee/config/app.toml
	# sed -i.bak -e "s/^pruning = \"default\"/pruning = \"nothing\"/" $HOME/.umee/config/app.toml
	sed -i '/\[grpc\]/{:a;n;/enabled/s/false/true/;Ta};/\[api\]/{:a;n;/enable/s/false/true/;Ta;}' $HOME/.umee/config/app.toml
	external_address=`curl ifconfig.me`
	peers="1694e2cd89b03270577e547d7d84ebef13e4eff1@172.105.168.226:26656,4d50abb293f399a0f41ef9dbebe62615d4c85e42@3.34.147.65:26656,d2447c2ba201fb5bdd7250921c7c267af18c0950@94.130.23.149:26656,901a625ecf43014cc383239524c5eb6595a56888@135.181.165.110:26656,4ea1dc6af45f0fad7315029d181ada53f7d3174c@161.97.182.71:26656,60a11b328f161fe8f3f98f85e838addb07513c9e@46.101.234.47:26656,03c8165065c925f3bf56be6d2b5aa820c5f8e26c@194.163.166.56:26656,4bf9ff17d148418aec04fdda9bff671e482457a3@213.202.252.173:26656,1fb83420fd2bf665dc886fb3727d809579d63e51@206.189.133.102:26656,b85598b96a9c8e835b7b2f2c0b322eb2317fe7cd@94.250.201.70:26656"
	sed -i.bak -e "s/^external_address = \"\"/external_address = \"$external_address:26656\"/; s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.umee/config/config.toml
	wget -O $HOME/.umee/config/addrbook.json https://api.nodes.guru/umee_addrbook.json
	installCosmovisor
	installGeth
	createServiceGeth
	installOrchestrator
	generateKeysOrchestrator
	createServiceOrchestrator
}

function updateSoftware {
	echo -e '\n\e[42mUpdate software\e[0m\n' && sleep 1
	mkdir -p $HOME/data
	systemctl stop gorc geth umeed
	umeed unsafe-reset-all
	cd $HOME
	rm -r $HOME/umee
	git clone --depth 1 --branch v0.3.0 https://github.com/umee-network/umee.git
	cd umee && make install
	umeed version
	rm $HOME/.umee/config/genesis.json
	umeed init ${UMEE_NODENAME} --chain-id $UMEE_CHAIN
	wget -O $HOME/.umee/config/genesis.json "https://github.com/umee-network/testnets/blob/main/networks/umeevengers-1c/genesis.json"
	peers="1694e2cd89b03270577e547d7d84ebef13e4eff1@172.105.168.226:26656,4d50abb293f399a0f41ef9dbebe62615d4c85e42@3.34.147.65:26656,d2447c2ba201fb5bdd7250921c7c267af18c0950@94.130.23.149:26656,901a625ecf43014cc383239524c5eb6595a56888@135.181.165.110:26656,4ea1dc6af45f0fad7315029d181ada53f7d3174c@161.97.182.71:26656,60a11b328f161fe8f3f98f85e838addb07513c9e@46.101.234.47:26656,03c8165065c925f3bf56be6d2b5aa820c5f8e26c@194.163.166.56:26656,4bf9ff17d148418aec04fdda9bff671e482457a3@213.202.252.173:26656,1fb83420fd2bf665dc886fb3727d809579d63e51@206.189.133.102:26656,b85598b96a9c8e835b7b2f2c0b322eb2317fe7cd@94.250.201.70:26656"
	sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.umee/config/config.toml
	# wget -O $HOME/.umee/config/addrbook.json https://api.nodes.guru/umee_addrbook.json
	# cd $HOME/umee
	# git reset --hard
	# git pull origin main
	# make install
	
	# createServiceGeth
	installOrchestrator
	systemctl restart umeed
}

function installService {
echo -e '\n\e[42mRunning\e[0m\n' && sleep 1
echo -e '\n\e[42mCreating a service\e[0m\n' && sleep 1

echo "[Unit]
Description=Cosmovisor Process Manager
After=network.target

[Service]
User=$USER
#Group=root
Type=simple
Environment=\"DAEMON_NAME=umeed\"
Environment=\"DAEMON_HOME=$HOME\"
Environment=\"DAEMON_RESTART_AFTER_UPGRADE=true\"
#Environment=\"DAEMON_ALLOW_DOWNLOAD_BINARIES=true\"
Environment=\"UNSAFE_SKIP_BACKUP=false\"
ExecStart=$HOME/cosmovisor/cosmovisor start
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target" > $HOME/umeed.service
sudo mv $HOME/umeed.service /etc/systemd/system
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1
sudo systemctl enable umeed
sudo systemctl restart umeed
echo -e '\n\e[42mCheck node status\e[0m\n' && sleep 1
if [[ `service umeed status | grep active` =~ "running" ]]; then
  echo -e "Your Umee node \e[32minstalled and works\e[39m!"
  echo -e "You can check node status by the command \e[7mservice umeed …
