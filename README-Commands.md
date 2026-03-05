# Dependencies
brew install lua ninja pkg-config ncurses pillow SDL2_ttf dylibbundler opengl

# Install
sudo gmake -lncursesw
## zsh:killed issue
if you ever get zsh: killed again after a rebuild, just run:
codesign -s - ~/repos/writing-env/wordgrinder/bin/wordgrinder-test

# Export Scripts


##	CC compiles C files with Homebrew’s Clang
##  CXX compiles C++ files with Homebrew’s Clang++
##	•	CXXFLAGS ensures access to C++ headers (like <algorithm> and <cassert>)
##	•	ARCHFLAGS="-arch arm64" targets Apple Silicon
sudo env 
    ARCHFLAGS="-arch arm64" 
    CC="/opt/homebrew/opt/llvm/bin/clang" 
    CXX="/opt/homebrew/opt/llvm/bin/clang++" 
    CFLAGS="-O2" 
    CXXFLAGS="-O2 -std=c++17 -I$(xcrun --show-sdk-path)/usr/include/c++/v1" 
    LDFLAGS="-L/opt/homebrew/opt/llvm/lib -lunwind" 
    sudo gmake clean all

# Newest Install Steps:
make
sudo cp /Users/alanmhernandez/repos/writing-env/wordgrinder/bin/wordgrinder-test /usr/local/bin/wordgrinder-test
sudo cp ~/repos/writing-env/wordgrinder/bin/wordgrinder-test /usr/local/bin/wordgrinder-test
sudo xattr -d com.apple.provenance /usr/local/bin/wordgrinder-test 2>/dev/null || true
sudo xattr -d com.apple.quarantine /usr/local/bin/wordgrinder-test 2>/dev/null || true
sudo codesign --force --sign - /usr/local/bin/wordgrinder-test
codesign --verify --verbose=4 /usr/local/bin/wordgrinder-test
