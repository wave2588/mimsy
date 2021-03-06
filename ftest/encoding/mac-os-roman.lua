-- Verify that Mimsy is able to load text documents formatted as Mac OS Roman.
function openedDoc(doc)
	local data = doc:data()
	doc:close()
	
	if data == 'Hello\226\128\162World' then
		ftest:expecterror('Read the file as Mac OS Roman')
	else
		ftest:failed(string.format('expected "Hello\226\128\162World" but found %q', data))
	end
end

function openFailed(reason)
	ftest:failed(reason)
end

-- can't use tmpfile because we need a file name
-- also lua doesn't support hex escape codes
local fname = '/tmp/mac-os-roman.txt'
local file = io.open(fname, 'w')
file:write('Hello\165World')	-- 'Hello World' with a bullet
file:close(file)

app:openfile(fname, 'openedDoc', 'openFailed')
