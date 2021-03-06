-- Verify that Mimsy is able to load text documents formatted as utf-32 big endian
-- with a bom.
function openedDoc(doc)
	local data = doc:data()
	doc:close()
	
	if data == 'Hello\226\128\162World' then
		ftest:passed()
	else
		ftest:failed(string.format('expected "Hello\226\128\162World" but found %q', data))
	end
end

function openFailed(reason)
	ftest:failed(reason)
end

-- can't use tmpfile because we need a file name
-- also lua doesn't support hex escape codes
local fname = '/tmp/utf-32-be-bom.txt'
local file = io.open(fname, 'w')
file:write('\0\0\254\255\0\0\0H\0\0\0e\0\0\0l\0\0\0l\0\0\0o\0\0\32\34\0\0\0W\0\0\0o\0\0\0r\0\0\0l\0\0\0d')	-- 'Hello World' with a bullet
file:close(file)

app:openfile(fname, 'openedDoc', 'openFailed')
