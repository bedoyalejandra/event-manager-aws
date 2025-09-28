exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ 
      message: "hOLIIII VENGOS DESDE EL CODIGO",
      function: "generate-report",
      reportId: "placeholder-report-id"
    })
  };
};